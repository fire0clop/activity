import uuid

from fastapi import APIRouter, status
from sqlalchemy import select

from app.core.deps import CurrentUser, DbSession
from app.core.exceptions import not_found
from app.models.subscription import Subscription
from app.schemas.subscription import SubscriptionCreateIn, SubscriptionOut, SubscriptionsOut

router = APIRouter(prefix="/subscriptions", tags=["subscriptions"])

MAX_SUBSCRIPTIONS_PER_USER = 20


def _out(sub: Subscription) -> SubscriptionOut:
    return SubscriptionOut(
        id=sub.id, category=sub.category,
        latitude=sub.latitude, longitude=sub.longitude, radius_km=sub.radius_km,
    )


@router.get("", response_model=SubscriptionsOut)
async def list_subscriptions(current_user: CurrentUser, db: DbSession) -> SubscriptionsOut:
    subs = (
        await db.execute(
            select(Subscription).where(Subscription.user_id == current_user.id)
            .order_by(Subscription.created_at)
        )
    ).scalars().all()
    return SubscriptionsOut(items=[_out(s) for s in subs])


@router.post("", response_model=SubscriptionOut, status_code=status.HTTP_201_CREATED)
async def create_subscription(
    body: SubscriptionCreateIn, current_user: CurrentUser, db: DbSession
) -> SubscriptionOut:
    from sqlalchemy import func

    from app.core.exceptions import AppError

    count = (
        await db.execute(
            select(func.count()).select_from(Subscription)
            .where(Subscription.user_id == current_user.id)
        )
    ).scalar() or 0
    if count >= MAX_SUBSCRIPTIONS_PER_USER:
        raise AppError("validation_error", "Слишком много подписок", 422)

    sub = Subscription(
        user_id=current_user.id,
        category=body.category,
        latitude=body.latitude,
        longitude=body.longitude,
        radius_km=body.radius_km,
    )
    db.add(sub)
    await db.commit()
    await db.refresh(sub)
    return _out(sub)


@router.delete("/{subscription_id}", status_code=status.HTTP_204_NO_CONTENT)
async def delete_subscription(
    subscription_id: uuid.UUID, current_user: CurrentUser, db: DbSession
) -> None:
    sub = (
        await db.execute(
            select(Subscription).where(
                Subscription.id == subscription_id,
                Subscription.user_id == current_user.id,
            )
        )
    ).scalar_one_or_none()
    if sub is None:
        raise not_found("Подписка не найдена")
    await db.delete(sub)
    await db.commit()
