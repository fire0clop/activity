import uuid
from datetime import UTC, datetime

from sqlalchemy import func, or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.event import Event
from app.models.participation import Participation
from app.models.report import Block
from app.models.user import User
from app.services import chat_service, push_service


async def accepted_count(db: AsyncSession, event_id: uuid.UUID) -> int:
    result = await db.execute(
        select(func.count()).select_from(Participation).where(
            Participation.event_id == event_id, Participation.status == "accepted"
        )
    )
    return int(result.scalar() or 0)


async def blocked_user_ids(db: AsyncSession, user_id: uuid.UUID) -> set[uuid.UUID]:
    """Все пользователи, скрытые от данного: кого он заблокировал И кто заблокировал его."""
    rows = await db.execute(
        select(Block.blocker_id, Block.blocked_id).where(
            or_(Block.blocker_id == user_id, Block.blocked_id == user_id)
        )
    )
    blocked: set[uuid.UUID] = set()
    for blocker_id, blocked_id in rows.all():
        blocked.add(blocked_id if blocker_id == user_id else blocker_id)
    return blocked


def format_time(event: Event) -> str:
    t = event.starts_at.strftime("%d.%m %H:%M UTC")
    return f"Точное время: {t}. Место: {event.address or '—'}"


async def on_accept(db: AsyncSession, event: Event, participant: User) -> None:
    """Побочные эффекты подтверждения участника: чат, раскрытие времени, счётчики, статус, push."""
    conv = await chat_service.get_or_create_event_conversation(db, event)
    await chat_service.ensure_member(db, conv.id, participant.id)
    await db.commit()

    await chat_service.post_message(
        db, conv.id, f"{participant.name} присоединился", sender_id=None, is_system=True
    )
    await chat_service.post_message(db, conv.id, format_time(event), sender_id=None, is_system=True)

    participant.events_attended += 1
    if event.max_participants is not None and await accepted_count(db, event.id) >= event.max_participants:
        event.status = "full"
    await db.commit()

    await push_service.send_push(
        db, participant.id, "Заявка принята",
        f"Вас приняли в «{event.title}». {format_time(event)}", {"event_id": str(event.id)},
    )


async def promote_waitlist(db: AsyncSession, event: Event) -> None:
    """Освободилось место → берём следующего из листа ожидания (по времени отклика)."""
    if event.status in ("cancelled", "finished", "closed"):
        return
    while event.max_participants is None or await accepted_count(db, event.id) < event.max_participants:
        nxt = (
            await db.execute(
                select(Participation)
                .where(Participation.event_id == event.id, Participation.status == "waitlisted")
                .order_by(Participation.created_at.asc())
                .limit(1)
            )
        ).scalar_one_or_none()
        if nxt is None:
            break
        nxt.status = "accepted"
        nxt.decided_at = datetime.now(UTC)
        await db.commit()
        participant = await db.get(User, nxt.user_id)
        await on_accept(db, event, participant)
