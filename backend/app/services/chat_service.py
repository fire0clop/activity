import logging
import uuid

from sqlalchemy import func, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.conversation import Conversation, ConversationMember
from app.models.event import Event
from app.models.message import Message
from app.models.user import User
from app.schemas.message import MessageOut
from app.schemas.user import UserPublic
from app.ws.manager import manager

logger = logging.getLogger("chat")


async def get_or_create_event_conversation(db: AsyncSession, event: Event) -> Conversation:
    result = await db.execute(select(Conversation).where(Conversation.event_id == event.id))
    conv = result.scalar_one_or_none()
    if conv is not None:
        return conv
    conv = Conversation(
        type="event",
        title=event.title,
        event_id=event.id,
        created_by=event.organizer_id,
    )
    db.add(conv)
    try:
        await db.flush()
    except IntegrityError:
        # Гонка: другой участник создал беседу параллельно (event_id UNIQUE) — берём существующую.
        await db.rollback()
        return (
            await db.execute(select(Conversation).where(Conversation.event_id == event.id))
        ).scalar_one()
    # организатор — владелец беседы
    db.add(ConversationMember(conversation_id=conv.id, user_id=event.organizer_id, role="owner"))
    return conv


async def ensure_member(db: AsyncSession, conversation_id: uuid.UUID, user_id: uuid.UUID) -> None:
    exists = await db.execute(
        select(ConversationMember.id).where(
            ConversationMember.conversation_id == conversation_id,
            ConversationMember.user_id == user_id,
        )
    )
    if exists.scalar_one_or_none() is None:
        db.add(ConversationMember(conversation_id=conversation_id, user_id=user_id, role="member"))


async def is_member(db: AsyncSession, conversation_id: uuid.UUID, user_id: uuid.UUID) -> bool:
    result = await db.execute(
        select(ConversationMember.id).where(
            ConversationMember.conversation_id == conversation_id,
            ConversationMember.user_id == user_id,
        )
    )
    return result.scalar_one_or_none() is not None


async def members_count(db: AsyncSession, conversation_id: uuid.UUID) -> int:
    result = await db.execute(
        select(func.count()).select_from(ConversationMember).where(
            ConversationMember.conversation_id == conversation_id
        )
    )
    return int(result.scalar() or 0)


def _message_out(msg: Message, sender: UserPublic | None) -> MessageOut:
    return MessageOut(
        id=msg.id,
        conversation_id=msg.conversation_id,
        sender=sender,
        text=msg.text,
        is_system=msg.is_system,
        created_at=msg.created_at,
    )


async def serialize_message(db: AsyncSession, msg: Message) -> MessageOut:
    sender = None
    if msg.sender_id is not None:
        user = await db.get(User, msg.sender_id)
        if user is not None:
            sender = UserPublic.from_model(user)
    return _message_out(msg, sender)


async def serialize_messages(db: AsyncSession, messages: list[Message]) -> list[MessageOut]:
    """Сериализует пачку сообщений одним запросом за отправителей (без N+1)."""
    sender_ids = {m.sender_id for m in messages if m.sender_id is not None}
    senders: dict[uuid.UUID, UserPublic] = {}
    if sender_ids:
        rows = (
            await db.execute(select(User).where(User.id.in_(sender_ids)))
        ).scalars().all()
        senders = {u.id: UserPublic.from_model(u) for u in rows}
    return [
        _message_out(m, senders.get(m.sender_id) if m.sender_id is not None else None)
        for m in messages
    ]


async def post_message(
    db: AsyncSession,
    conversation_id: uuid.UUID,
    text: str,
    sender_id: uuid.UUID | None,
    is_system: bool = False,
) -> MessageOut:
    msg = Message(
        conversation_id=conversation_id,
        sender_id=sender_id,
        text=text,
        is_system=is_system,
    )
    db.add(msg)
    await db.commit()
    await db.refresh(msg)

    out = await serialize_message(db, msg)
    await manager.broadcast(
        conversation_id,
        {"type": "system" if is_system else "message", "message": out.model_dump(mode="json")},
    )
    if not is_system and sender_id is not None:
        try:
            await _notify_offline_members(conversation_id, sender_id, out)
        except Exception:  # noqa: BLE001 - сбой пуша не должен ломать отправку сообщения
            logger.exception("chat: offline push failed")
    return out


async def _notify_offline_members(
    conversation_id: uuid.UUID, sender_id: uuid.UUID, msg: MessageOut
) -> None:
    """Пуш о новом сообщении тем участникам, кто сейчас не в чате (deep-link по conversation_id).

    Работает в СВОЕЙ короткоживущей сессии: нельзя растягивать транзакцию
    сессии-отправителя на время рассылки (висящая 'idle in transaction'
    блокирует DDL и чужие запросы).
    """
    from app.db.session import SessionLocal
    from app.services import push_service

    online = set(await manager.online_user_ids(conversation_id))
    sender_name = msg.sender.name if msg.sender else "Кто-то"
    async with SessionLocal() as db:
        member_ids = (
            await db.execute(
                select(ConversationMember.user_id).where(
                    ConversationMember.conversation_id == conversation_id
                )
            )
        ).scalars().all()
        conv = await db.get(Conversation, conversation_id)
        title = (conv.title if conv else None) or "Новое сообщение"
        for uid in member_ids:
            if uid == sender_id or str(uid) in online:
                continue
            await push_service.send_push(
                db, uid, title, f"{sender_name}: {msg.text[:120]}",
                {"conversation_id": str(conversation_id)},
            )
