import asyncio
import logging
from datetime import UTC, datetime, timedelta

from sqlalchemy import or_, select, update

from app.db.session import SessionLocal
from app.models.conversation import Conversation
from app.models.event import Event

logger = logging.getLogger("lifecycle")

SWEEP_INTERVAL_SEC = 300
# Если у события нет ends_at, считаем завершённым через STALE_HOURS после начала.
STALE_HOURS = 6


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
        await db.execute(update(Event).where(Event.id.in_(rows)).values(status="finished"))
        await db.execute(
            update(Conversation).where(Conversation.event_id.in_(rows)).values(is_archived=True)
        )
        await db.commit()
        return len(rows)


async def run_sweeper() -> None:
    """Фоновая задача: периодически переводит прошедшие события в finished и архивирует чаты."""
    while True:
        try:
            n = await _sweep_once()
            if n:
                logger.info("lifecycle: finished %d past events", n)
        except asyncio.CancelledError:
            break
        except Exception:  # noqa: BLE001
            logger.exception("lifecycle sweep failed")
        await asyncio.sleep(SWEEP_INTERVAL_SEC)
