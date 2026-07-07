"""Подписки на новые события: матчинг и рассылка пушей при публикации."""

import logging

from geoalchemy2 import Geography
from sqlalchemy import and_, cast, func, or_, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.event import Event
from app.models.subscription import Subscription

logger = logging.getLogger("subscriptions")

MAX_NOTIFICATIONS_PER_EVENT = 200  # предохранитель от рассылки на весь город


async def notify_subscribers(db: AsyncSession, event: Event) -> int:
    """Шлёт пуш подписчикам, чьи критерии совпали с новым событием. Возвращает число пушей.

    Гео-матчинг считается в БД через PostGIS ST_DWithin (а не хаверсином в event loop):
    не загружаем все подписки в память и применяем LIMIT на уровне запроса.
    """
    from app.services import push_service

    event_point = cast(
        func.ST_SetSRID(func.ST_MakePoint(event.longitude, event.latitude), 4326), Geography()
    )
    sub_point = cast(
        func.ST_SetSRID(func.ST_MakePoint(Subscription.longitude, Subscription.latitude), 4326),
        Geography(),
    )
    # Гео-подписка попадает по радиусу; подписка без координат (только категория) — всегда.
    geo_ok = or_(
        Subscription.latitude.is_(None),
        func.ST_DWithin(sub_point, event_point, Subscription.radius_km * 1000),
    )
    if event.category is not None:
        category_ok = (Subscription.category.is_(None)) | (Subscription.category == event.category)
    else:
        category_ok = Subscription.category.is_(None)

    # Матч: подписка на этого организатора ЛИБО критерий-подписка (категория+гео) по событию.
    organizer_follow = Subscription.target_organizer_id == event.organizer_id
    criteria = and_(Subscription.target_organizer_id.is_(None), category_ok, geo_ok)

    query = (
        select(Subscription.user_id)
        .where(
            Subscription.user_id != event.organizer_id,
            or_(organizer_follow, criteria),
        )
        .distinct()
        .limit(MAX_NOTIFICATIONS_PER_EVENT)
    )

    user_ids = (await db.execute(query)).scalars().all()
    for user_id in user_ids:
        await push_service.send_push(
            db, user_id, "Новое событие по подписке",
            f"«{event.title}» — {event.address or 'рядом с вами'}",
            {"event_id": str(event.id)},
        )
    return len(user_ids)
