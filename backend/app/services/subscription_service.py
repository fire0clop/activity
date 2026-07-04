"""Подписки на новые события: матчинг и рассылка пушей при публикации."""

import logging
import math
import uuid

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.event import Event
from app.models.subscription import Subscription

logger = logging.getLogger("subscriptions")

MAX_NOTIFICATIONS_PER_EVENT = 200  # предохранитель от рассылки на весь город


def _distance_km(lat1: float, lng1: float, lat2: float, lng2: float) -> float:
    """Хаверсин: расстояние по сфере в километрах."""
    r = 6371.0
    p1, p2 = math.radians(lat1), math.radians(lat2)
    dp = math.radians(lat2 - lat1)
    dl = math.radians(lng2 - lng1)
    a = math.sin(dp / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
    return 2 * r * math.asin(math.sqrt(a))


def _matches(sub: Subscription, event: Event) -> bool:
    if sub.category is not None and sub.category != event.category:
        return False
    if sub.latitude is not None and sub.longitude is not None:
        dist = _distance_km(sub.latitude, sub.longitude, event.latitude, event.longitude)
        if dist > sub.radius_km:
            return False
    return True


async def notify_subscribers(db: AsyncSession, event: Event) -> int:
    """Шлёт пуш подписчикам, чьи критерии совпали с новым событием. Возвращает число пушей."""
    from app.services import push_service

    query = select(Subscription).where(Subscription.user_id != event.organizer_id)
    if event.category is not None:
        # категория подписки либо не задана (гео-подписка), либо совпадает
        query = query.where(
            (Subscription.category.is_(None)) | (Subscription.category == event.category)
        )
    else:
        query = query.where(Subscription.category.is_(None))
    subs = (await db.execute(query)).scalars().all()

    notified: set[uuid.UUID] = set()
    for sub in subs:
        if len(notified) >= MAX_NOTIFICATIONS_PER_EVENT:
            logger.warning("subscriptions: notification cap hit for event %s", event.id)
            break
        if sub.user_id in notified or not _matches(sub, event):
            continue
        await push_service.send_push(
            db, sub.user_id, "Новое событие по подписке",
            f"«{event.title}» — {event.address or 'рядом с вами'}",
            {"event_id": str(event.id)},
        )
        notified.add(sub.user_id)
    return len(notified)
