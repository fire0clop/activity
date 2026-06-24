import uuid

from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.conversation import Conversation, ConversationMember
from app.models.event import Event
from app.models.message import Message
from app.models.user import User
from app.schemas.message import MessageOut
from app.schemas.user import UserPublic
from app.ws.manager import manager


async def get_or_create_event_conversation(db: AsyncSession, event: Event) -> Conversation:
    result = await db.execute(select(Conversation).where(Conversation.event_id == event.id))
    conv = result.scalar_one_or_none()
    if conv is None:
        conv = Conversation(
            type="event",
            title=event.title,
            event_id=event.id,
            created_by=event.organizer_id,
        )
        db.add(conv)
        await db.flush()
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
    return out
