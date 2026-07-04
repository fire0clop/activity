import logging

from fastapi import APIRouter
from sqlalchemy import text

from app.api.v1 import (
    auth,
    chat,
    conversations,
    events,
    participations,
    reports,
    reviews,
    subscriptions,
    users,
)
from app.core.deps import DbSession, RedisDep

logger = logging.getLogger("health")

api_router = APIRouter()


@api_router.get("/health", tags=["health"])
async def health(db: DbSession, redis: RedisDep) -> dict:
    """Deep-health: проверяет доступность БД и Redis."""
    checks = {"db": False, "redis": False}
    try:
        await db.execute(text("SELECT 1"))
        checks["db"] = True
    except Exception:  # noqa: BLE001
        logger.warning("health: db check failed", exc_info=True)
    try:
        await redis.ping()
        checks["redis"] = True
    except Exception:  # noqa: BLE001
        logger.warning("health: redis check failed", exc_info=True)
    ok = all(checks.values())
    return {"status": "ok" if ok else "degraded", "checks": checks}


api_router.include_router(auth.router)
api_router.include_router(users.router)
api_router.include_router(events.router)
api_router.include_router(participations.router)
api_router.include_router(conversations.router)
api_router.include_router(reviews.router)
api_router.include_router(reports.router)
api_router.include_router(subscriptions.router)
api_router.include_router(chat.router)  # WebSocket /ws/chat/{conversation_id}
