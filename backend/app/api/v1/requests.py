import uuid
from datetime import UTC, datetime

from fastapi import APIRouter, Query, status
from geoalchemy2 import Geography
from sqlalchemy import Float, cast, func, literal, select

from app.core.config import settings
from app.core.deps import CompleteUser, CurrentUser, DbSession, RedisDep
from app.core.exceptions import conflict, forbidden, not_found
from app.models.request import CompanyRequest, RequestSupport
from app.models.user import User
from app.schemas.request import RequestCreateIn, RequestItem, RequestsOut, SupportOut
from app.schemas.user import UserBrief
from app.services import content_filter, matching_service, request_service
from app.services.pagination import decode_cursor, encode_cursor
from app.services.rate_limit import check_user_action

router = APIRouter(prefix="/requests", tags=["requests"])


def _build(
    req: CompanyRequest,
    author: User,
    *,
    viewer_id: uuid.UUID,
    supports: int,
    i_support: bool,
    distance_km: float | None,
) -> RequestItem:
    return RequestItem(
        id=req.id,
        author=UserBrief.from_model(author),
        category=req.category,
        text=req.text,
        area=req.area,
        radius_km=req.radius_km,
        when_window=req.when_window,
        status=req.status,
        supports_count=supports,
        i_support=i_support,
        is_mine=req.author_id == viewer_id,
        distance_km=distance_km,
        latitude=req.latitude,
        longitude=req.longitude,
        fulfilled_event_id=req.fulfilled_event_id,
        created_at=req.created_at,
        expires_at=req.expires_at,
    )


@router.post("", response_model=RequestItem, status_code=status.HTTP_201_CREATED)
async def create_request(
    body: RequestCreateIn, current_user: CompleteUser, db: DbSession, redis: RedisDep
) -> RequestItem:
    """Сказать, чего хочешь, не беря на себя организацию."""
    await check_user_action(
        redis, current_user.id, "create_request", settings.user_rl_requests_per_hour, 3600
    )
    content_filter.ensure_clean(body.text)
    req = CompanyRequest(
        author_id=current_user.id,
        category=body.category,
        text=body.text,
        location=func.ST_SetSRID(func.ST_MakePoint(body.longitude, body.latitude), 4326),
        latitude=body.latitude,
        longitude=body.longitude,
        area=body.area,
        radius_km=body.radius_km,
        when_window=body.when_window,
        status="open",
        expires_at=request_service.expiry_for(body.when_window),
    )
    db.add(req)
    await db.commit()
    await db.refresh(req)
    return _build(req, current_user, viewer_id=current_user.id,
                  supports=0, i_support=False, distance_km=0.0)


@router.get("", response_model=RequestsOut)
async def list_requests(
    current_user: CurrentUser,
    db: DbSession,
    # Без координат — режим «везде»: та же лента, но без привязки к городу.
    lat: float | None = Query(None, ge=-90, le=90),
    lng: float | None = Query(None, ge=-180, le=180),
    radius_km: float = Query(25, gt=0, le=500),
    category: str | None = None,
    limit: int = Query(20, ge=1, le=100),
    cursor: str | None = None,
) -> RequestsOut:
    """Живой спрос рядом: чего люди хотят, но пока никто не организовал."""
    offset = decode_cursor(cursor)
    everywhere = lat is None or lng is None
    point = (
        None if everywhere
        else cast(func.ST_SetSRID(func.ST_MakePoint(lng, lat), 4326), Geography())
    )
    distance_m = (
        literal(None, type_=Float).label("distance_m") if everywhere
        else func.ST_Distance(CompanyRequest.location, point).label("distance_m")
    )

    supports_sq = (
        select(func.count())
        .select_from(RequestSupport)
        .where(RequestSupport.request_id == CompanyRequest.id)
        .correlate(CompanyRequest)
        .scalar_subquery()
    )
    mine_sq = (
        select(func.count())
        .select_from(RequestSupport)
        .where(
            RequestSupport.request_id == CompanyRequest.id,
            RequestSupport.user_id == current_user.id,
        )
        .correlate(CompanyRequest)
        .scalar_subquery()
    )

    filters = [
        CompanyRequest.status == "open",
        CompanyRequest.expires_at > datetime.now(UTC),
    ]
    if not everywhere:
        filters.append(func.ST_DWithin(CompanyRequest.location, point, radius_km * 1000))
    blocked = await matching_service.blocked_user_ids(db, current_user.id)
    if blocked:
        filters.append(CompanyRequest.author_id.notin_(blocked))
    if category:
        filters.append(CompanyRequest.category == category)

    rows = (
        await db.execute(
            select(CompanyRequest, User, distance_m, supports_sq, mine_sq)
            .join(User, User.id == CompanyRequest.author_id)
            .where(*filters)
            # Сначала то, чего хотят многие: спрос важнее свежести.
            .order_by(supports_sq.desc(), distance_m.asc())
            .offset(offset)
            .limit(limit + 1)
        )
    ).all()

    has_more = len(rows) > limit
    rows = rows[:limit]
    items = [
        _build(req, author, viewer_id=current_user.id, supports=int(supports),
               i_support=bool(mine),
               # В режиме «везде» расстояния нет — считать его не от чего.
               distance_km=round(float(dist) / 1000, 2) if dist is not None else None)
        for req, author, dist, supports, mine in rows
    ]
    return RequestsOut(
        items=items, next_cursor=encode_cursor(offset + limit) if has_more else None
    )


@router.get("/mine", response_model=RequestsOut)
async def my_requests(current_user: CurrentUser, db: DbSession) -> RequestsOut:
    rows = (
        await db.execute(
            select(CompanyRequest)
            .where(CompanyRequest.author_id == current_user.id)
            .order_by(CompanyRequest.created_at.desc())
        )
    ).scalars().all()
    items = [
        _build(req, current_user, viewer_id=current_user.id,
               supports=await request_service.supports_count(db, req.id),
               i_support=False, distance_km=None)
        for req in rows
    ]
    return RequestsOut(items=items, next_cursor=None)


@router.post("/{request_id}/support", response_model=SupportOut)
async def support_request(
    request_id: uuid.UUID, current_user: CompleteUser, db: DbSession
) -> SupportOut:
    """«Я тоже хочу» — сигнал спроса, ради которого запросы и существуют."""
    req = await db.get(CompanyRequest, request_id)
    if req is None:
        raise not_found("Запрос не найден")
    if req.author_id == current_user.id:
        raise conflict("own_request", "Это ваш запрос")
    if req.status != "open":
        raise conflict("request_closed", "Запрос уже неактуален")

    exists = (
        await db.execute(
            select(RequestSupport).where(
                RequestSupport.request_id == request_id,
                RequestSupport.user_id == current_user.id,
            )
        )
    ).scalar_one_or_none()
    if exists is None:  # идемпотентно
        db.add(RequestSupport(request_id=request_id, user_id=current_user.id))
        await db.commit()
    return SupportOut(
        supports_count=await request_service.supports_count(db, request_id), i_support=True
    )


@router.delete("/{request_id}/support", response_model=SupportOut)
async def unsupport_request(
    request_id: uuid.UUID, current_user: CurrentUser, db: DbSession
) -> SupportOut:
    row = (
        await db.execute(
            select(RequestSupport).where(
                RequestSupport.request_id == request_id,
                RequestSupport.user_id == current_user.id,
            )
        )
    ).scalar_one_or_none()
    if row is not None:
        await db.delete(row)
        await db.commit()
    return SupportOut(
        supports_count=await request_service.supports_count(db, request_id), i_support=False
    )


@router.delete("/{request_id}", status_code=status.HTTP_204_NO_CONTENT)
async def cancel_request(
    request_id: uuid.UUID, current_user: CurrentUser, db: DbSession
) -> None:
    req = await db.get(CompanyRequest, request_id)
    if req is None:
        raise not_found("Запрос не найден")
    if req.author_id != current_user.id:
        raise forbidden("Снять запрос может только автор")
    req.status = "cancelled"
    await db.commit()
