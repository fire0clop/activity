import asyncio
import logging
from datetime import UTC, datetime, timedelta

from sqlalchemy import or_, select, update

from app.db.session import SessionLocal
from app.models.conversation import Conversation
from app.models.event import Event
from app.models.participation import Participation
from app.services import matching_service

logger = logging.getLogger("lifecycle")

SWEEP_INTERVAL_SEC = 300
# Если у события нет ends_at, считаем завершённым через STALE_HOURS после начала.
STALE_HOURS = 6

# Окна напоминаний: (нижняя граница, верхняя граница, флаг, фраза). Условие попадания:
# now + lower < starts_at <= now + upper. Окна не пересекаются — каждое событие получает
# «суточное» и «двухчасовое» напоминание ровно по одному разу.
REMINDER_WINDOWS = [
    (timedelta(hours=2), timedelta(hours=24), "reminder_24h_sent", "в ближайшие сутки"),
    (timedelta(0), timedelta(hours=2), "reminder_2h_sent", "меньше чем через 2 часа"),
]


async def _sweep_once() -> int:
    now = datetime.now(UTC)
    stale_before = now - timedelta(hours=STALE_HOURS)
    async with SessionLocal() as db:
        rows = (
            await db.execute(
                select(Event.id).where(
                    Event.status.in_(["open", "full"]),
                    or_(
                        Event.ends_at < now,
                        (Event.ends_at.is_(None)) & (Event.starts_at < stale_before),
                    ),
                )
            )
        ).scalars().all()
        if not rows:
            return 0
        # Клонируем повторяющиеся ДО смены статуса (нужны исходные данные события).
        recurring = (
            await db.execute(
                select(Event).where(Event.id.in_(rows), Event.recurrence == "weekly")
            )
        ).scalars().all()
        for ev in recurring:
            await matching_service.clone_recurring_event(db, ev)

        await db.execute(update(Event).where(Event.id.in_(rows)).values(status="finished"))
        await db.execute(
            update(Conversation).where(Conversation.event_id.in_(rows)).values(is_archived=True)
        )
        # Засчитываем посещение accepted-участникам авто-завершённых событий.
        await matching_service.mark_attended(db, list(rows))
        await db.commit()
        return len(rows)


async def _send_reminders_once() -> int:
    """Шлёт напоминания accepted-участникам событий, попавших в окно. Возвращает число пушей."""
    from app.services import push_service

    now = datetime.now(UTC)
    sent_total = 0
    async with SessionLocal() as db:
        for lower, upper, flag_attr, phrase in REMINDER_WINDOWS:
            events = (
                await db.execute(
                    select(Event).where(
                        Event.status.in_(["open", "full"]),
                        Event.starts_at > now + lower,
                        Event.starts_at <= now + upper,
                        getattr(Event, flag_attr).is_(False),
                    )
                )
            ).scalars().all()
            for event in events:
                user_ids = (
                    await db.execute(
                        select(Participation.user_id).where(
                            Participation.event_id == event.id,
                            Participation.status == "accepted",
                        )
                    )
                ).scalars().all()
                for uid in user_ids:
                    await push_service.send_push(
                        db, uid, "Напоминание о событии",
                        f"«{event.title}» — {phrase}. Не забудьте!",
                        {"event_id": str(event.id)},
                    )
                setattr(event, flag_attr, True)
                sent_total += len(user_ids)
        await db.commit()
    return sent_total


async def run_sweeper() -> None:
    """Фоновая задача: авто-финиш прошедших событий, архивация чатов, напоминания участникам."""
    while True:
        try:
            n = await _sweep_once()
            if n:
                logger.info("lifecycle: finished %d past events", n)
            r = await _send_reminders_once()
            if r:
                logger.info("lifecycle: sent %d reminders", r)
        except asyncio.CancelledError:
            break
        except Exception:  # noqa: BLE001
            logger.exception("lifecycle sweep failed")
        await asyncio.sleep(SWEEP_INTERVAL_SEC)
