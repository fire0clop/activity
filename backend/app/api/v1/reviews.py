import uuid

from fastapi import APIRouter, Query, status
from sqlalchemy import func, select

from app.core.deps import CompleteUser, CurrentUser, DbSession
from app.core.exceptions import AppError, conflict, forbidden, not_found
from app.models.event import Event
from app.models.participation import Participation
from app.models.review import Review
from app.models.user import User
from app.schemas.review import ReviewCreateIn, ReviewOut, ReviewsOut
from app.schemas.user import UserPublic
from app.services.pagination import decode_cursor, encode_cursor

router = APIRouter(tags=["reviews"])


async def _recalc_rating(db: DbSession, target_id: uuid.UUID) -> None:
    result = await db.execute(
        select(func.avg(Review.rating), func.count()).where(Review.target_id == target_id)
    )
    avg, count = result.one()
    user = await db.get(User, target_id)
    if user is not None:
        user.rating_avg = round(float(avg or 0), 2)
        user.rating_count = int(count or 0)


@router.post("/events/{event_id}/reviews", response_model=ReviewOut,
             status_code=status.HTTP_201_CREATED)
async def create_review(
    event_id: uuid.UUID, body: ReviewCreateIn, current_user: CompleteUser, db: DbSession
) -> ReviewOut:
    event = await db.get(Event, event_id)
    if event is None:
        raise not_found("Событие не найдено")
    if event.status != "finished":
        raise AppError("validation_error", "Отзыв можно оставить после завершения события", 422)

    if body.target_id == current_user.id:
        raise forbidden("Нельзя оставить отзыв самому себе")

    # Отзыв вправе оставить только принятый участник или организатор события.
    is_organizer = event.organizer_id == current_user.id
    if not is_organizer:
        is_participant = (
            await db.execute(
                select(Participation.id).where(
                    Participation.event_id == event_id,
                    Participation.user_id == current_user.id,
                    Participation.status == "accepted",
                )
            )
        ).scalar_one_or_none() is not None
        if not is_participant:
            raise forbidden("Отзыв доступен только участникам события")

    existing = await db.execute(
        select(Review).where(
            Review.event_id == event_id,
            Review.author_id == current_user.id,
            Review.target_id == body.target_id,
        )
    )
    if existing.scalar_one_or_none() is not None:
        raise conflict("already_reviewed", "Вы уже оставили отзыв")

    review = Review(
        event_id=event_id,
        author_id=current_user.id,
        target_id=body.target_id,
        rating=body.rating,
        comment=body.comment,
    )
    db.add(review)
    await db.flush()
    await _recalc_rating(db, body.target_id)
    await db.commit()
    await db.refresh(review)

    return ReviewOut(
        id=review.id,
        event_id=review.event_id,
        author=UserPublic.from_model(current_user),
        target_id=review.target_id,
        rating=review.rating,
        comment=review.comment,
        created_at=review.created_at,
    )


@router.get("/users/{user_id}/reviews", response_model=ReviewsOut)
async def list_user_reviews(
    user_id: uuid.UUID,
    _: CurrentUser,
    db: DbSession,
    limit: int = Query(20, ge=1, le=100),
    cursor: str | None = None,
) -> ReviewsOut:
    offset = decode_cursor(cursor)
    # JOIN с автором — без N+1 (раньше был db.get(User) на каждую строку).
    rows = (
        await db.execute(
            select(Review, User)
            .join(User, User.id == Review.author_id)
            .where(Review.target_id == user_id)
            .order_by(Review.created_at.desc())
            .offset(offset)
            .limit(limit + 1)
        )
    ).all()

    has_more = len(rows) > limit
    rows = rows[:limit]
    items: list[ReviewOut] = [
        ReviewOut(
            id=r.id,
            event_id=r.event_id,
            author=UserPublic.from_model(author),
            target_id=r.target_id,
            rating=r.rating,
            comment=r.comment,
            created_at=r.created_at,
        )
        for r, author in rows
    ]
    next_cursor = encode_cursor(offset + limit) if has_more else None
    return ReviewsOut(items=items, next_cursor=next_cursor)
