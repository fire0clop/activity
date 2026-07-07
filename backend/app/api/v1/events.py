import uuid
from datetime import UTC, datetime, time, timedelta

from fastapi import APIRouter, File, Query, UploadFile, status
from geoalchemy2 import Geography
from sqlalchemy import String, cast, func, or_, select

from app.core.config import settings
from app.core.deps import CompleteUser, CurrentUser, DbSession, RedisDep
from app.core.exceptions import forbidden, not_found
from app.models.conversation import Conversation
from app.models.event import Event
from app.models.participation import Participation
from app.models.user import User
from app.schemas.event import (
    EventCreateIn,
    EventDetail,
    EventListOut,
    EventUpdateIn,
    PhotosOut,
)
from app.schemas.user import UserBrief
from app.services import event_service, matching_service
from app.services.pagination import decode_cursor, encode_cursor
from app.services.rate_limit import check_user_action
from app.services.storage_service import get_storage

MAX_EVENT_PHOTOS = 5

router = APIRouter(prefix="/events", tags=["events"])


async def _conversation_id(db: DbSession, event_id: uuid.UUID) -> uuid.UUID | None:
    return (
        await db.execute(select(Conversation.id).where(Conversation.event_id == event_id))
    ).scalar_one_or_none()


async def _accepted_briefs(db: DbSession, event_id: uuid.UUID, limit: int = 12) -> list[UserBrief]:
    rows = (
        await db.execute(
            select(User)
            .join(Participation, Participation.user_id == User.id)
            .where(Participation.event_id == event_id, Participation.status == "accepted")
            .order_by(Participation.decided_at.asc())
            .limit(limit)
        )
    ).scalars().all()
    return [
        UserBrief(id=u.id, name=u.name, avatar_url=u.avatar_url, rating_avg=float(u.rating_avg))
        for u in rows
    ]


def _when_range(when: str) -> tuple[datetime, datetime]:
    today = datetime.now(UTC).date()

    def start_of(d):
        return datetime.combine(d, time.min, tzinfo=UTC)

    if when == "today":
        return start_of(today), start_of(today + timedelta(days=1))
    if when == "tomorrow":
        return start_of(today + timedelta(days=1)), start_of(today + timedelta(days=2))
    saturday = today + timedelta(days=(5 - today.weekday()) % 7)
    return start_of(saturday), start_of(saturday + timedelta(days=2))


@router.post("", response_model=EventDetail, status_code=status.HTTP_201_CREATED)
async def create_event(
    body: EventCreateIn, current_user: CompleteUser, db: DbSession, redis: RedisDep
) -> EventDetail:
    from app.core.exceptions import AppError
    await check_user_action(
        redis, current_user.id, "create_event", settings.user_rl_events_per_hour, 3600
    )
    if body.starts_at < datetime.now(UTC):
        raise AppError("validation_error", "Время начала должно быть в будущем", 422)

    # Координаты: из ссылки Яндекс.Карт (точнее) или напрямую.
    lat, lng = body.latitude, body.longitude
    if body.map_url:
        import asyncio

        from app.services.geo_service import parse_location
        try:
            # Жёсткий потолок на весь разбор (внешний сервис + редиректы), чтобы зависший
            # map_url не удерживал воркер/соединение неограниченно.
            coords = await asyncio.wait_for(
                asyncio.to_thread(parse_location, body.map_url), timeout=15
            )
        except TimeoutError as exc:
            raise AppError(
                "geo_timeout",
                "Не удалось обработать ссылку на карту вовремя. Попробуйте ещё раз или пришлите координаты.",
                503,
            ) from exc
        if coords is None:
            raise AppError(
                "validation_error",
                "Не удалось распознать точку по ссылке. Пришлите ссылку на конкретное место из Яндекс.Карт.",
                422,
            )
        lat, lng = coords

    event = Event(
        organizer_id=current_user.id,
        title=body.title,
        description=body.description,
        category=body.category,
        starts_at=body.starts_at,
        ends_at=body.ends_at,
        location=func.ST_SetSRID(func.ST_MakePoint(lng, lat), 4326),
        latitude=lat,
        longitude=lng,
        address=body.address,
        map_url=body.map_url,
        min_participants=body.min_participants,
        max_participants=body.max_participants,
        price=body.price,
        price_split=body.price_split,
        auto_accept=body.auto_accept,
        recurrence=body.recurrence,
        status="open",
    )
    db.add(event)
    current_user.events_created += 1
    await db.flush()
    db.add(Participation(event_id=event.id, user_id=current_user.id, status="accepted",
                         decided_at=datetime.now(UTC)))
    await db.commit()
    await db.refresh(event)

    # Пуш подписчикам на категорию/район; сбой рассылки не ломает создание.
    try:
        from app.services.subscription_service import notify_subscribers
        await notify_subscribers(db, event)
    except Exception:  # noqa: BLE001
        import logging
        logging.getLogger("subscriptions").exception("notify failed for event %s", event.id)

    return event_service.build_detail(
        event, current_user, viewer_id=current_user.id, my_status="accepted",
        participants_current=1, distance_km=0.0, conversation_id=None,
    )


@router.get("", response_model=EventListOut)
async def list_events(
    current_user: CurrentUser,
    db: DbSession,
    lat: float = Query(..., ge=-90, le=90),
    lng: float = Query(..., ge=-180, le=180),
    radius_km: float = Query(10, gt=0, le=500),
    when: str | None = Query(None, pattern="^(today|tomorrow|weekend)$"),
    date_from: datetime | None = Query(None, alias="from"),
    date_to: datetime | None = Query(None, alias="to"),
    category: str | None = None,
    query: str | None = None,
    limit: int = Query(20, ge=1, le=100),
    cursor: str | None = None,
) -> EventListOut:
    point = cast(func.ST_SetSRID(func.ST_MakePoint(lng, lat), 4326), Geography())
    distance_m = func.ST_Distance(Event.location, point).label("distance_m")

    # Агрегаты одним запросом (без N+1): кол-во accepted и мой статус — коррелированными подзапросами.
    accepted_sq = (
        select(func.count())
        .select_from(Participation)
        .where(Participation.event_id == Event.id, Participation.status == "accepted")
        .correlate(Event)
        .scalar_subquery()
    )
    my_status_sq = (
        select(Participation.status)
        .where(Participation.event_id == Event.id, Participation.user_id == current_user.id)
        .correlate(Event)
        .scalar_subquery()
    )

    stmt = (
        select(Event, User, distance_m, accepted_sq.label("cnt"), my_status_sq.label("my"))
        .join(User, User.id == Event.organizer_id)
        .where(func.ST_DWithin(Event.location, point, radius_km * 1000))
        .where(Event.status.in_(["open", "full"]))
    )

    blocked = await matching_service.blocked_user_ids(db, current_user.id)
    if blocked:
        stmt = stmt.where(Event.organizer_id.notin_(blocked))

    if when:
        w_from, w_to = _when_range(when)
        stmt = stmt.where(Event.starts_at >= w_from, Event.starts_at < w_to)
    if date_from:
        stmt = stmt.where(Event.starts_at >= date_from)
    if date_to:
        stmt = stmt.where(Event.starts_at < date_to)
    if category:
        stmt = stmt.where(Event.category == category)
    if query:
        # Экранируем спецсимволы LIKE, чтобы '%' и '_' в запросе искались буквально.
        escaped = query.replace("\\", "\\\\").replace("%", "\\%").replace("_", "\\_")
        like = f"%{escaped}%"
        stmt = stmt.where(
            Event.title.ilike(like, escape="\\")
            | cast(Event.description, String).ilike(like, escape="\\")
        )

    offset = decode_cursor(cursor)
    stmt = stmt.order_by(Event.starts_at.asc()).offset(offset).limit(limit + 1)

    rows = (await db.execute(stmt)).all()
    has_more = len(rows) > limit
    rows = rows[:limit]

    items = [
        event_service.build_list_item(
            event, organizer, viewer_id=current_user.id, my_status=my,
            participants_current=int(cnt or 0),
            distance_km=round(distance / 1000, 2) if distance is not None else None,
        )
        for event, organizer, distance, cnt, my in rows
    ]
    next_cursor = encode_cursor(offset + limit) if has_more else None
    return EventListOut(items=items, next_cursor=next_cursor)


@router.get("/mine", response_model=EventListOut)
async def my_events(
    current_user: CurrentUser,
    db: DbSession,
    limit: int = Query(50, ge=1, le=100),
) -> EventListOut:
    """Мои события: которые я организую ИЛИ в которых участвую, включая завершённые.

    Основная лента отдаёт только open/full — так пользователь не мог найти свою историю.
    Порядок — от ближайших/будущих к прошлым (starts_at по убыванию).
    """
    my_part_sq = (
        select(Participation.event_id)
        .where(
            Participation.user_id == current_user.id,
            Participation.status.in_(["accepted", "pending", "waitlisted"]),
        )
    )
    accepted_sq = (
        select(func.count())
        .select_from(Participation)
        .where(Participation.event_id == Event.id, Participation.status == "accepted")
        .correlate(Event)
        .scalar_subquery()
    )
    my_status_sq = (
        select(Participation.status)
        .where(Participation.event_id == Event.id, Participation.user_id == current_user.id)
        .correlate(Event)
        .scalar_subquery()
    )
    stmt = (
        select(Event, User, accepted_sq.label("cnt"), my_status_sq.label("my"))
        .join(User, User.id == Event.organizer_id)
        .where(or_(Event.organizer_id == current_user.id, Event.id.in_(my_part_sq)))
        .order_by(Event.starts_at.desc())
        .limit(limit)
    )
    rows = (await db.execute(stmt)).all()
    items = [
        event_service.build_list_item(
            event, organizer, viewer_id=current_user.id, my_status=my,
            participants_current=int(cnt or 0), distance_km=None,
        )
        for event, organizer, cnt, my in rows
    ]
    return EventListOut(items=items, next_cursor=None)


@router.get("/{event_id}", response_model=EventDetail)
async def get_event(event_id: uuid.UUID, current_user: CurrentUser, db: DbSession) -> EventDetail:
    event = await db.get(Event, event_id)
    if event is None:
        raise not_found("Событие не найдено")
    organizer = await db.get(User, event.organizer_id)
    count = await matching_service.accepted_count(db, event.id)
    my = (
        await db.execute(
            select(Participation.status).where(
                Participation.event_id == event.id, Participation.user_id == current_user.id
            )
        )
    ).scalar_one_or_none()
    conv = await _conversation_id(db, event.id)
    accepted = await _accepted_briefs(db, event.id)
    return event_service.build_detail(
        event, organizer, viewer_id=current_user.id, my_status=my,
        participants_current=count, distance_km=None, conversation_id=conv, accepted=accepted,
    )


@router.patch("/{event_id}", response_model=EventDetail)
async def update_event(
    event_id: uuid.UUID, body: EventUpdateIn, current_user: CurrentUser, db: DbSession
) -> EventDetail:
    event = await db.get(Event, event_id)
    if event is None:
        raise not_found("Событие не найдено")
    if event.organizer_id != current_user.id:
        raise forbidden("Только организатор может изменять событие")

    data = body.model_dump(exclude_unset=True)
    # Если меняют ссылку на точку — пересчитываем координаты.
    if data.get("map_url"):
        import asyncio

        from app.core.exceptions import AppError
        from app.services.geo_service import parse_location
        coords = await asyncio.to_thread(parse_location, data["map_url"])
        if coords is None:
            raise AppError("validation_error", "Не удалось распознать точку по ссылке", 422)
        event.latitude, event.longitude = coords
        event.location = func.ST_SetSRID(func.ST_MakePoint(coords[1], coords[0]), 4326)
    for field, value in data.items():
        setattr(event, field, value)
    await db.commit()
    await db.refresh(event)

    count = await matching_service.accepted_count(db, event.id)
    conv = await _conversation_id(db, event.id)
    return event_service.build_detail(
        event, current_user, viewer_id=current_user.id, my_status="accepted",
        participants_current=count, distance_km=None, conversation_id=conv,
    )


@router.delete("/{event_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_event(event_id: uuid.UUID, current_user: CurrentUser, db: DbSession) -> None:
    event = await db.get(Event, event_id)
    if event is None:
        raise not_found("Событие не найдено")
    if event.organizer_id != current_user.id:
        raise forbidden("Только организатор может отменить событие")
    event.status = "cancelled"
    conv = await db.execute(select(Conversation).where(Conversation.event_id == event.id))
    c = conv.scalar_one_or_none()
    if c is not None:
        c.is_archived = True
    await db.commit()


@router.post("/{event_id}/finish", response_model=EventDetail)
async def finish_event(event_id: uuid.UUID, current_user: CurrentUser, db: DbSession) -> EventDetail:
    """Завершить событие (организатор). Делает возможными отзывы и архивирует чат."""
    event = await db.get(Event, event_id)
    if event is None:
        raise not_found("Событие не найдено")
    if event.organizer_id != current_user.id:
        raise forbidden("Только организатор может завершить событие")
    already_finished = event.status == "finished"
    event.status = "finished"
    conv = await db.execute(select(Conversation).where(Conversation.event_id == event.id))
    c = conv.scalar_one_or_none()
    if c is not None:
        c.is_archived = True
    # Посещение засчитываем один раз — при первом переводе в finished.
    if not already_finished:
        await matching_service.mark_attended(db, [event.id])
        await matching_service.clone_recurring_event(db, event)  # следующее вхождение (weekly)
    await db.commit()
    await db.refresh(event)

    count = await matching_service.accepted_count(db, event.id)
    return event_service.build_detail(
        event, current_user, viewer_id=current_user.id, my_status="accepted",
        participants_current=count, distance_km=None, conversation_id=c.id if c else None,
    )


@router.post("/{event_id}/cover")
async def upload_cover(
    event_id: uuid.UUID, current_user: CompleteUser, db: DbSession, file: UploadFile = File(...)
) -> dict:
    event = await db.get(Event, event_id)
    if event is None:
        raise not_found("Событие не найдено")
    if event.organizer_id != current_user.id:
        raise forbidden("Только организатор может менять обложку")
    storage = get_storage()
    url = await storage.save(file, subdir="covers")
    event.cover_url = url
    await db.commit()
    return {"cover_url": url}


@router.post("/{event_id}/photos", response_model=PhotosOut)
async def upload_photo(
    event_id: uuid.UUID, current_user: CompleteUser, db: DbSession, file: UploadFile = File(...)
) -> PhotosOut:
    event = await db.get(Event, event_id)
    if event is None:
        raise not_found("Событие не найдено")
    if event.organizer_id != current_user.id:
        raise forbidden("Только организатор может добавлять фото")
    photos = list(event.photo_urls or [])
    if len(photos) >= MAX_EVENT_PHOTOS:
        from app.core.exceptions import AppError
        raise AppError("validation_error", f"Не больше {MAX_EVENT_PHOTOS} фото", 422)
    url = await get_storage().save(file, subdir="events")
    photos.append(url)
    event.photo_urls = photos
    await db.commit()
    return PhotosOut(photo_urls=photos)


@router.delete("/{event_id}/photos", response_model=PhotosOut)
async def delete_photo(
    event_id: uuid.UUID, current_user: CompleteUser, db: DbSession, url: str = Query(...)
) -> PhotosOut:
    event = await db.get(Event, event_id)
    if event is None:
        raise not_found("Событие не найдено")
    if event.organizer_id != current_user.id:
        raise forbidden("Только организатор может удалять фото")
    photos = [p for p in (event.photo_urls or []) if p != url]
    event.photo_urls = photos
    await db.commit()
    await get_storage().delete(url)
    return PhotosOut(photo_urls=photos)
