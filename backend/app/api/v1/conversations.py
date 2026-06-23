import uuid

from fastapi import APIRouter, Query, status
from sqlalchemy import func, select

from app.core.deps import CompleteUser, CurrentUser, DbSession
from app.core.exceptions import forbidden, not_found
from app.models.conversation import Conversation, ConversationMember
from app.models.event import Event
from app.models.message import Message
from app.models.user import User
from app.schemas.conversation import (
    AddMembersIn,
    ConversationDetail,
    ConversationListItem,
    ConversationListOut,
    CreateGroupIn,
    LastMessage,
    UpdateConversationIn,
)
from app.schemas.message import MessagesOut
from app.schemas.user import UserPublic
from app.services import chat_service
from app.services.pagination import decode_cursor, encode_cursor

router = APIRouter(prefix="/conversations", tags=["conversations"])


async def _avatar_url(db: DbSession, conv: Conversation) -> str | None:
    if conv.type == "event" and conv.event_id:
        event = await db.get(Event, conv.event_id)
        return event.cover_url if event else None
    return None


async def _last_message(db: DbSession, conv_id: uuid.UUID) -> tuple[Message | None, LastMessage | None]:
    result = await db.execute(
        select(Message).where(Message.conversation_id == conv_id)
        .order_by(Message.created_at.desc()).limit(1)
    )
    msg = result.scalar_one_or_none()
    if msg is None:
        return None, None
    sender_name = None
    if msg.sender_id:
        sender = await db.get(User, msg.sender_id)
        sender_name = sender.name if sender else None
    return msg, LastMessage(text=msg.text, created_at=msg.created_at, sender_name=sender_name)


async def _unread_count(db: DbSession, conv_id: uuid.UUID, member: ConversationMember) -> int:
    base = select(func.count()).select_from(Message).where(Message.conversation_id == conv_id)
    if member.last_read_message_id is None:
        return int((await db.execute(base)).scalar() or 0)
    last_read = await db.get(Message, member.last_read_message_id)
    if last_read is None:
        return int((await db.execute(base)).scalar() or 0)
    return int((await db.execute(base.where(Message.created_at > last_read.created_at))).scalar() or 0)


async def _build_list_item(
    db: DbSession,
    conv: Conversation,
    member: ConversationMember,
    members_count: int | None = None,
) -> ConversationListItem:
    _, last = await _last_message(db, conv.id)
    if members_count is None:
        members_count = await chat_service.members_count(db, conv.id)
    return ConversationListItem(
        id=conv.id,
        type=conv.type,
        title=conv.title,
        avatar_url=await _avatar_url(db, conv),
        event_id=conv.event_id,
        members_count=members_count,
        last_message=last,
        unread_count=await _unread_count(db, conv.id, member),
        is_archived=conv.is_archived,
    )


async def _get_membership(db: DbSession, conv_id: uuid.UUID, user_id: uuid.UUID) -> ConversationMember:
    result = await db.execute(
        select(ConversationMember).where(
            ConversationMember.conversation_id == conv_id,
            ConversationMember.user_id == user_id,
        )
    )
    member = result.scalar_one_or_none()
    if member is None:
        raise forbidden("Вы не участник беседы")
    return member


@router.get("", response_model=ConversationListOut)
async def list_conversations(
    current_user: CurrentUser,
    db: DbSession,
    limit: int = Query(20, ge=1, le=100),
    cursor: str | None = None,
) -> ConversationListOut:
    offset = decode_cursor(cursor)
    memberships = (
        await db.execute(
            select(ConversationMember)
            .where(ConversationMember.user_id == current_user.id)
            .offset(offset)
            .limit(limit + 1)
        )
    ).scalars().all()

    has_more = len(memberships) > limit
    memberships = memberships[:limit]

    conv_ids = [m.conversation_id for m in memberships]
    # Батчим тяжёлые фан-ауты одним запросом каждый (раньше — N запросов на список).
    convs_by_id: dict[uuid.UUID, Conversation] = {}
    counts_by_conv: dict[uuid.UUID, int] = {}
    if conv_ids:
        conv_rows = (
            await db.execute(select(Conversation).where(Conversation.id.in_(conv_ids)))
        ).scalars().all()
        convs_by_id = {c.id: c for c in conv_rows}

        count_rows = (
            await db.execute(
                select(ConversationMember.conversation_id, func.count())
                .where(ConversationMember.conversation_id.in_(conv_ids))
                .group_by(ConversationMember.conversation_id)
            )
        ).all()
        counts_by_conv = {cid: int(n) for cid, n in count_rows}

    items: list[ConversationListItem] = []
    for m in memberships:
        conv = convs_by_id.get(m.conversation_id)
        if conv is not None:
            items.append(
                await _build_list_item(
                    db, conv, m, members_count=counts_by_conv.get(conv.id, 0)
                )
            )

    next_cursor = encode_cursor(offset + limit) if has_more else None
    return ConversationListOut(items=items, next_cursor=next_cursor)


@router.get("/{conversation_id}", response_model=ConversationDetail)
async def get_conversation(
    conversation_id: uuid.UUID, current_user: CurrentUser, db: DbSession
) -> ConversationDetail:
    member = await _get_membership(db, conversation_id, current_user.id)
    conv = await db.get(Conversation, conversation_id)
    if conv is None:
        raise not_found("Беседа не найдена")

    member_rows = (
        await db.execute(
            select(ConversationMember.user_id).where(
                ConversationMember.conversation_id == conversation_id
            )
        )
    ).scalars().all()
    members = []
    for uid in member_rows:
        user = await db.get(User, uid)
        if user:
            members.append(UserPublic.from_model(user))

    base = await _build_list_item(db, conv, member)
    return ConversationDetail(**base.model_dump(), members=members, my_role=member.role)


@router.get("/{conversation_id}/messages", response_model=MessagesOut)
async def get_messages(
    conversation_id: uuid.UUID,
    current_user: CurrentUser,
    db: DbSession,
    limit: int = Query(50, ge=1, le=100),
    cursor: str | None = None,
) -> MessagesOut:
    await _get_membership(db, conversation_id, current_user.id)
    offset = decode_cursor(cursor)
    rows = (
        await db.execute(
            select(Message)
            .where(Message.conversation_id == conversation_id)
            .order_by(Message.created_at.desc())
            .offset(offset)
            .limit(limit + 1)
        )
    ).scalars().all()

    has_more = len(rows) > limit
    rows = rows[:limit]
    items = await chat_service.serialize_messages(db, list(rows))
    next_cursor = encode_cursor(offset + limit) if has_more else None
    return MessagesOut(items=items, next_cursor=next_cursor)


# --- V2 (этап 12): самостоятельные группы ---------------------------------

@router.post("", response_model=ConversationDetail, status_code=status.HTTP_201_CREATED)
async def create_group(
    body: CreateGroupIn, current_user: CompleteUser, db: DbSession
) -> ConversationDetail:
    conv = Conversation(type="group", title=body.title, created_by=current_user.id)
    db.add(conv)
    await db.flush()
    db.add(ConversationMember(conversation_id=conv.id, user_id=current_user.id, role="owner"))

    member_ids = set(body.member_ids)
    if body.from_event_id:
        accepted = (
            await db.execute(
                select(ConversationMember.user_id).join(
                    Conversation, Conversation.id == ConversationMember.conversation_id
                ).where(Conversation.event_id == body.from_event_id)
            )
        ).scalars().all()
        member_ids.update(accepted)

    member_ids.discard(current_user.id)
    for uid in member_ids:
        db.add(ConversationMember(conversation_id=conv.id, user_id=uid, role="member"))
    await db.commit()

    return await get_conversation(conv.id, current_user, db)  # переиспользуем сериализацию


@router.patch("/{conversation_id}", response_model=ConversationDetail)
async def update_conversation(
    conversation_id: uuid.UUID, body: UpdateConversationIn, current_user: CurrentUser, db: DbSession
) -> ConversationDetail:
    member = await _get_membership(db, conversation_id, current_user.id)
    if member.role != "owner":
        raise forbidden("Только владелец может менять беседу")
    conv = await db.get(Conversation, conversation_id)
    if body.title is not None:
        conv.title = body.title
    await db.commit()
    return await get_conversation(conversation_id, current_user, db)


@router.post("/{conversation_id}/members", response_model=ConversationDetail)
async def add_members(
    conversation_id: uuid.UUID, body: AddMembersIn, current_user: CurrentUser, db: DbSession
) -> ConversationDetail:
    member = await _get_membership(db, conversation_id, current_user.id)
    if member.role != "owner":
        raise forbidden("Только владелец может добавлять участников")
    for uid in body.user_ids:
        await chat_service.ensure_member(db, conversation_id, uid)
    await db.commit()
    return await get_conversation(conversation_id, current_user, db)


@router.delete("/{conversation_id}/members/{user_id}", status_code=status.HTTP_204_NO_CONTENT)
async def remove_member(
    conversation_id: uuid.UUID, user_id: uuid.UUID, current_user: CurrentUser, db: DbSession
) -> None:
    member = await _get_membership(db, conversation_id, current_user.id)
    if member.role != "owner":
        raise forbidden("Только владелец может удалять участников")
    target = await db.execute(
        select(ConversationMember).where(
            ConversationMember.conversation_id == conversation_id,
            ConversationMember.user_id == user_id,
        )
    )
    row = target.scalar_one_or_none()
    if row is not None:
        await db.delete(row)
        await db.commit()


@router.post("/{conversation_id}/leave", status_code=status.HTTP_204_NO_CONTENT)
async def leave_conversation(
    conversation_id: uuid.UUID, current_user: CurrentUser, db: DbSession
) -> None:
    member = await _get_membership(db, conversation_id, current_user.id)
    await db.delete(member)
    await db.commit()
