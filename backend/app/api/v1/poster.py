"""Афиша: чужие мероприятия, на которые можно сходить.

Пользователь здесь ничего не создаёт — карточки заводит оператор. Смысл раздела
двойной: он даёт городу содержание в тот период, когда собственных событий ещё
мало, и служит поводом для настоящего сбора («идём вместе на этот концерт»).
"""

import uuid
from datetime import UTC, datetime

from fastapi import APIRouter, Query, status
from geoalchemy2 import Geography
from sqlalchemy import cast, func, select

from app.api.v1.admin import AdminGuard
from app.core.deps import CurrentUser, DbSession
from app.core.exceptions import not_found
from app.models.event import Event
from app.models.poster import PosterEvent
from app.schemas.poster import (
    PosterCreateIn,
    PosterItem,
    PosterOut,
    PosterUpdateIn,
)
from app.services.pagination import decode_cursor, encode_cursor

router = APIRouter(prefix="/poster", tags=["poster"])


def _build(poster: PosterEvent, *, distance_km: float | None, gatherings: int) -> PosterItem:
    return PosterItem(
        id=poster.id,
        title=poster.title,
        description=poster.description,
        category=poster.category,
        starts_at=poster.starts_at,
        ends_at=poster.ends_at,
        venue=poster.venue,
        address=poster.address,
        latitude=poster.latitude,
        longitude=poster.longitude,
        distance_km=distance_km,
        price_from=float(poster.price_from) if poster.price_from is not None else None,
        is_free=poster.is_free,
        image_url=poster.image_url,
        source_url=poster.source_url,
        source_name=poster.source_name,
        gatherings_count=gatherings,
        status=poster.status,
    )


@router.get("", response_model=PosterOut)
async def list_poster(
    _: CurrentUser,
    db: DbSession,
    lat: float = Query(..., ge=-90, le=90),
    lng: float = Query(..., ge=-180, le=180),
    radius_km: float = Query(50, gt=0, le=500),
    category: str | None = None,
    when: str | None = Query(None, pattern="^(today|tomorrow|weekend)$"),
    limit: int = Query(20, ge=1, le=100),
    cursor: str | None = None,
) -> PosterOut:
    """Что идёт рядом. Радиус шире, чем у событий: на концерт ездят дальше, чем гулять."""
    offset = decode_cursor(cursor)
    point = cast(func.ST_SetSRID(func.ST_MakePoint(lng, lat), 4326), Geography())
    distance_m = func.ST_Distance(PosterEvent.location, point).label("distance_m")

    gatherings_sq = (
        select(func.count())
        .select_from(Event)
        .where(Event.poster_id == PosterEvent.id, Event.status.in_(["open", "full"]))
        .correlate(PosterEvent)
        .scalar_subquery()
    )

    filters = [
        PosterEvent.status == "published",
        PosterEvent.starts_at >= datetime.now(UTC),
        func.ST_DWithin(PosterEvent.location, point, radius_km * 1000),
    ]
    if category:
        filters.append(PosterEvent.category == category)
    if when:
        from app.api.v1.events import _when_range

        w_from, w_to = _when_range(when)
        filters += [PosterEvent.starts_at >= w_from, PosterEvent.starts_at < w_to]

    rows = (
        await db.execute(
            select(PosterEvent, distance_m, gatherings_sq)
            .where(*filters)
            .order_by(PosterEvent.starts_at.asc())
            .offset(offset)
            .limit(limit + 1)
        )
    ).all()

    has_more = len(rows) > limit
    rows = rows[:limit]
    return PosterOut(
        items=[
            _build(p, distance_km=round(float(dist) / 1000, 1), gatherings=int(g))
            for p, dist, g in rows
        ],
        next_cursor=encode_cursor(offset + limit) if has_more else None,
    )


@router.get("/{poster_id}", response_model=PosterItem)
async def get_poster(poster_id: uuid.UUID, _: CurrentUser, db: DbSession) -> PosterItem:
    poster = await db.get(PosterEvent, poster_id)
    if poster is None or poster.status != "published":
        raise not_found("Мероприятие не найдено")
    gatherings = (
        await db.execute(
            select(func.count()).select_from(Event).where(
                Event.poster_id == poster_id, Event.status.in_(["open", "full"])
            )
        )
    ).scalar() or 0
    return _build(poster, distance_km=None, gatherings=int(gatherings))


# --- Операторские ручки ---------------------------------------------------


@router.post("", response_model=PosterItem, status_code=status.HTTP_201_CREATED)
async def create_poster(body: PosterCreateIn, _: AdminGuard, db: DbSession) -> PosterItem:
    poster = PosterEvent(
        **body.model_dump(exclude={"latitude", "longitude"}),
        latitude=body.latitude,
        longitude=body.longitude,
        location=func.ST_SetSRID(func.ST_MakePoint(body.longitude, body.latitude), 4326),
        status="published",
    )
    db.add(poster)
    await db.commit()
    await db.refresh(poster)
    return _build(poster, distance_km=None, gatherings=0)


@router.patch("/{poster_id}", response_model=PosterItem)
async def update_poster(
    poster_id: uuid.UUID, body: PosterUpdateIn, _: AdminGuard, db: DbSession
) -> PosterItem:
    poster = await db.get(PosterEvent, poster_id)
    if poster is None:
        raise not_found("Мероприятие не найдено")
    for field, value in body.model_dump(exclude_unset=True).items():
        setattr(poster, field, value)
    await db.commit()
    await db.refresh(poster)
    return _build(poster, distance_km=None, gatherings=0)


@router.post("/import", response_model=list[dict])
async def import_poster(
    _: AdminGuard,
    db: DbSession,
    city: str | None = Query(None, description="Город источника; по умолчанию все"),
    limit: int = Query(200, ge=1, le=500),
) -> list[dict]:
    """Подтянуть афишу из внешнего источника.

    Идемпотентно: карточки опознаются по ключу источника, повторный вызов обновляет
    даты, а не плодит дубликаты. Тот же импорт запускается сам раз в шесть часов.
    """
    from app.services import poster_import

    if city:
        if city not in poster_import.CITIES:
            raise not_found(f"Город не поддерживается источником: {city}")
        return [await poster_import.import_city(db, city, limit=limit)]
    return await poster_import.import_all(db, limit=limit)


@router.delete("/{poster_id}", status_code=status.HTTP_204_NO_CONTENT)
async def hide_poster(poster_id: uuid.UUID, _: AdminGuard, db: DbSession) -> None:
    """Снимаем с публикации, а не удаляем: на карточку могут ссылаться собранные события."""
    poster = await db.get(PosterEvent, poster_id)
    if poster is None:
        raise not_found("Мероприятие не найдено")
    poster.status = "hidden"
    await db.commit()
