"""Связи, заработанные встречами.

Ключевое правило продукта: право на контакт даёт совместная встреча, а не поиск по
каталогу. Знакомый — тот, с кем вы были в составе одного и того же завершённого
события. Отсюда растут личный чат и приглашения: и то и другое открывается фактом,
который уже случился офлайн, поэтому холодного контакта в приложении не появляется.
"""

import uuid
from dataclasses import dataclass
from datetime import datetime

from sqlalchemy import and_, func, or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.conversation import Conversation, ConversationMember
from app.models.event import Event
from app.models.participation import Participation
from app.models.subscription import Subscription
from app.models.user import User


@dataclass(slots=True)
class Connection:
    user: User
    meetings: int
    last_met_at: datetime
    last_event_title: str
    i_follow: bool
    follows_me: bool

    @property
    def mutual(self) -> bool:
        """Взаимная подписка — это уже «свои», а не просто знакомые."""
        return self.i_follow and self.follows_me


def _my_finished_events(user_id: uuid.UUID):
    """Подзапрос: завершённые события, где пользователь был в составе."""
    return (
        select(Participation.event_id)
        .join(Event, Event.id == Participation.event_id)
        .where(
            Participation.user_id == user_id,
            Participation.status == "accepted",
            Event.status == "finished",
        )
        .scalar_subquery()
    )


async def met_user_ids(db: AsyncSession, user_id: uuid.UUID) -> set[uuid.UUID]:
    """С кем пользователь реально пересекался на завершённых событиях."""
    rows = (
        await db.execute(
            select(Participation.user_id)
            .where(
                Participation.event_id.in_(_my_finished_events(user_id)),
                Participation.status == "accepted",
                Participation.user_id != user_id,
            )
            .distinct()
        )
    ).scalars().all()
    return set(rows)


async def have_met(db: AsyncSession, a: uuid.UUID, b: uuid.UUID) -> bool:
    """Была ли у двоих хотя бы одна общая завершённая встреча."""
    if a == b:
        return False
    found = (
        await db.execute(
            select(Participation.id)
            .where(
                Participation.event_id.in_(_my_finished_events(a)),
                Participation.status == "accepted",
                Participation.user_id == b,
            )
            .limit(1)
        )
    ).scalar_one_or_none()
    return found is not None


async def list_connections(db: AsyncSession, user_id: uuid.UUID) -> list[Connection]:
    """Знакомые: сколько раз пересекались и когда виделись в последний раз.

    Три запроса без N+1: пересечения, профили, подписки в обе стороны.
    """
    rows = (
        await db.execute(
            select(Participation.user_id, Event.title, Event.starts_at)
            .join(Event, Event.id == Participation.event_id)
            .where(
                Participation.event_id.in_(_my_finished_events(user_id)),
                Participation.status == "accepted",
                Participation.user_id != user_id,
            )
        )
    ).all()
    if not rows:
        return []

    # Сводим в Python: у одного человека совместных событий единицы, отдельный
    # оконный запрос ради этого не нужен.
    agg: dict[uuid.UUID, tuple[int, datetime, str]] = {}
    for other_id, title, starts_at in rows:
        meetings, last_at, last_title = agg.get(other_id, (0, starts_at, title))
        if starts_at >= last_at:
            last_at, last_title = starts_at, title
        agg[other_id] = (meetings + 1, last_at, last_title)

    users = (
        await db.execute(select(User).where(User.id.in_(agg.keys())))
    ).scalars().all()

    follow_rows = (
        await db.execute(
            select(Subscription.user_id, Subscription.target_organizer_id).where(
                or_(
                    and_(
                        Subscription.user_id == user_id,
                        Subscription.target_organizer_id.in_(agg.keys()),
                    ),
                    and_(
                        Subscription.target_organizer_id == user_id,
                        Subscription.user_id.in_(agg.keys()),
                    ),
                )
            )
        )
    ).all()
    i_follow = {target for follower, target in follow_rows if follower == user_id}
    follows_me = {follower for follower, target in follow_rows if target == user_id}

    result = [
        Connection(
            user=u,
            meetings=agg[u.id][0],
            last_met_at=agg[u.id][1],
            last_event_title=agg[u.id][2],
            i_follow=u.id in i_follow,
            follows_me=u.id in follows_me,
        )
        for u in users
    ]
    # Сначала «свои», потом по свежести встречи.
    result.sort(key=lambda c: (not c.mutual, -c.last_met_at.timestamp()))
    return result


async def get_or_create_direct(
    db: AsyncSession, a: uuid.UUID, b: uuid.UUID
) -> Conversation:
    """Личная беседа двоих. Идемпотентна: повторный вызов возвращает ту же.

    Право на неё проверяет вызывающая сторона (`have_met`) — сервис лишь хранит
    инвариант «в direct-беседе ровно два участника».
    """
    # Беседа, где ровно два участника и оба — это a и b.
    existing_id = (
        await db.execute(
            select(ConversationMember.conversation_id)
            .join(Conversation, Conversation.id == ConversationMember.conversation_id)
            .where(Conversation.type == "direct", ConversationMember.user_id.in_((a, b)))
            .group_by(ConversationMember.conversation_id)
            .having(func.count() == 2)
            .limit(1)
        )
    ).scalar_one_or_none()
    if existing_id is not None:
        existing = await db.get(Conversation, existing_id)
        if existing is not None:
            return existing

    conv = Conversation(type="direct", title=None, created_by=a)
    db.add(conv)
    await db.flush()
    db.add(ConversationMember(conversation_id=conv.id, user_id=a, role="member"))
    db.add(ConversationMember(conversation_id=conv.id, user_id=b, role="member"))
    await db.commit()
    await db.refresh(conv)
    return conv


async def direct_peer_ids(
    db: AsyncSession, conversation_ids: list[uuid.UUID], viewer_id: uuid.UUID
) -> dict[uuid.UUID, uuid.UUID]:
    """Для списка личных бесед — кто в них собеседник (заголовок и аватар берём у него)."""
    if not conversation_ids:
        return {}
    rows = (
        await db.execute(
            select(ConversationMember.conversation_id, ConversationMember.user_id).where(
                ConversationMember.conversation_id.in_(conversation_ids),
                ConversationMember.user_id != viewer_id,
            )
        )
    ).all()
    return {conv_id: user_id for conv_id, user_id in rows}
