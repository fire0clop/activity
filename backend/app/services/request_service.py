"""Обслуживание запросов «Ищу компанию»."""

import logging
import uuid
from datetime import UTC, datetime, time, timedelta

from sqlalchemy import select, update
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.event import Event
from app.models.request import CompanyRequest, RequestSupport
from app.services import push_service

logger = logging.getLogger("requests")

WHEN_WINDOWS = ("today", "tomorrow", "weekend", "week")


def expiry_for(window: str, *, now: datetime | None = None) -> datetime:
    """Когда желание протухает.

    Живёт ровно столько, сколько имеет смысл: «сегодня» — до конца дня, «на выходных» —
    до конца воскресенья. Иначе лента запросов быстро превращается в кладбище.
    """
    now = now or datetime.now(UTC)
    today = now.date()

    def end_of(d) -> datetime:
        return datetime.combine(d, time.max, tzinfo=UTC)

    if window == "today":
        return end_of(today)
    if window == "tomorrow":
        return end_of(today + timedelta(days=1))
    if window == "weekend":
        # Ближайшее воскресенье (если сегодня воскресенье — сегодня).
        sunday = today + timedelta(days=(6 - today.weekday()) % 7)
        return end_of(sunday)
    return end_of(today + timedelta(days=7))


async def supports_count(db: AsyncSession, request_id: uuid.UUID) -> int:
    from sqlalchemy import func

    return int(
        (
            await db.execute(
                select(func.count()).select_from(RequestSupport).where(
                    RequestSupport.request_id == request_id
                )
            )
        ).scalar()
        or 0
    )


async def expire_stale(db: AsyncSession, *, now: datetime | None = None) -> int:
    """Пометить протухшие запросы. Вызывается фоновым обходом вместе с событиями."""
    now = now or datetime.now(UTC)
    result = await db.execute(
        update(CompanyRequest)
        .where(CompanyRequest.status == "open", CompanyRequest.expires_at < now)
        .values(status="expired")
    )
    return result.rowcount or 0


async def fulfill(db: AsyncSession, request: CompanyRequest, event: Event) -> None:
    """Кто-то взял запрос на себя: помечаем выполненным и зовём заинтересованных.

    Пуш идёт автору и всем, кто поставил «+1»: именно ради них запрос и висел.
    """
    request.status = "fulfilled"
    request.fulfilled_event_id = event.id
    await db.commit()

    supporters = (
        await db.execute(
            select(RequestSupport.user_id).where(RequestSupport.request_id == request.id)
        )
    ).scalars().all()

    when = event.starts_at.strftime("%d.%m в %H:%M")
    recipients = {request.author_id, *supporters} - {event.organizer_id}
    for uid in recipients:
        title = "Ваше «хочу» сбылось" if uid == request.author_id else "Собирают то, что вы хотели"
        await push_service.send_push(
            db, uid, title,
            f"«{event.title}» — {when} (UTC). Откликнитесь, пока есть места",
            {"event_id": str(event.id)},
        )
