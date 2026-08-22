import asyncio
import contextlib
import logging
from datetime import UTC, datetime, timedelta

import redis.asyncio as aioredis
from sqlalchemy import or_, select, update

from app.core.config import settings
from app.db.session import SessionLocal
from app.models.conversation import Conversation
from app.models.event import Event
from app.models.participation import Participation
from app.services import matching_service, request_service

logger = logging.getLogger("lifecycle")


async def _claim(redis: aioredis.Redis, key: str, ttl: int) -> bool:
    """Захватить право выполнить цикл. True — этот процесс работает, остальные пропускают.

    Gunicorn поднимает несколько воркеров, и каждый запускает свои фоновые задачи.
    Без этого замка обход выполнялся бы по числу воркеров: участники получали бы
    столько же одинаковых напоминаний, а повторяющееся событие клонировалось бы
    в стольких же экземплярах. Замок живёт чуть меньше интервала, поэтому
    следующий цикл снова свободен, а падение держателя не блокирует работу дольше
    одного периода.
    """
    try:
        return bool(await redis.set(key, "1", nx=True, ex=ttl))
    except Exception:  # noqa: BLE001 - недоступность Redis не должна останавливать обслуживание
        logger.warning("не удалось взять замок %s — цикл пропущен", key, exc_info=True)
        return False

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


async def _expire_requests_once() -> int:
    """Протухшие «хочу» убираем из ленты запросов — иначе она станет кладбищем."""
    async with SessionLocal() as db:
        n = await request_service.expire_stale(db)
        await db.commit()
        return n


async def run_poster_import() -> None:
    """Обновление афиши из внешнего источника.

    Отдельной задачей, а не внутри свипера: свипер ходит раз в пять минут, а дёргать
    чужой API с такой частотой незачем — расписание мероприятий так быстро не меняется.
    """
    from app.services import poster_import

    interval = settings.poster_import_interval_hours * 3600
    redis = aioredis.from_url(settings.redis_url, decode_responses=True)
    try:
        while True:
            try:
                if await _claim(redis, "lifecycle:poster_import", int(interval * 0.9)):
                    async with SessionLocal() as db:
                        stats = await poster_import.import_all(db)
                    total = sum(s["created"] + s["updated"] for s in stats)
                    if total:
                        logger.info("афиша обновлена: %s", stats)
            except asyncio.CancelledError:
                break
            except Exception:  # noqa: BLE001 - сбой источника не должен ронять приложение
                logger.exception("не удалось обновить афишу")
            await asyncio.sleep(interval)
    finally:
        with contextlib.suppress(Exception):
            await redis.aclose()


async def run_sweeper() -> None:
    """Фоновая задача: авто-финиш прошедших событий, архивация чатов, напоминания участникам."""
    redis = aioredis.from_url(settings.redis_url, decode_responses=True)
    try:
        while True:
            try:
                # Обход шлёт пуши и клонирует повторяющиеся события — выполнять его
                # должен ровно один процесс, иначе всё это удвоится по числу воркеров.
                if await _claim(redis, "lifecycle:sweep", int(SWEEP_INTERVAL_SEC * 0.9)):
                    n = await _sweep_once()
                    if n:
                        logger.info("lifecycle: finished %d past events", n)
                    r = await _send_reminders_once()
                    if r:
                        logger.info("lifecycle: sent %d reminders", r)
                    e = await _expire_requests_once()
                    if e:
                        logger.info("lifecycle: expired %d company requests", e)
            except asyncio.CancelledError:
                break
            except Exception:  # noqa: BLE001
                logger.exception("lifecycle sweep failed")
            await asyncio.sleep(SWEEP_INTERVAL_SEC)
    finally:
        with contextlib.suppress(Exception):
            await redis.aclose()
