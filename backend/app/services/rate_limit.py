"""Per-user rate-limit на спам-действия (фиксированное окно в Redis).

IP-лимит в middleware защищает от анонимных всплесков; эти лимиты — от спама
авторизованных пользователей (создание событий, отклики, жалобы, сообщения),
их нельзя обойти сменой IP.
"""

import logging
import time
import uuid

from redis.asyncio import Redis

from app.core.config import settings
from app.core.exceptions import AppError

logger = logging.getLogger("rate_limit")


def _rate_limited(retry_after_sec: int) -> AppError:
    return AppError(
        "rate_limited",
        "Слишком много действий, попробуйте позже",
        429,
        headers={"Retry-After": str(retry_after_sec)},
    )


async def check_user_action(
    redis: Redis, user_id: uuid.UUID, action: str, limit: int, window_sec: int
) -> None:
    """Бросает 429 rate_limited, если пользователь превысил limit за окно window_sec.

    При недоступном Redis действие пропускается (как и IP-лимит) — деградация
    в сторону доступности, с warning в логе.
    """
    if not settings.user_rate_limit_enabled:
        return
    window = int(time.time() // window_sec)
    key = f"url:{action}:{user_id}:{window}"
    try:
        count = await redis.incr(key)
        if count == 1:
            await redis.expire(key, window_sec)
    except Exception:  # noqa: BLE001 - Redis недоступен → не блокируем действие
        logger.warning("user rate limit: Redis unavailable, action passed", exc_info=True)
        return
    if count > limit:
        raise _rate_limited(window_sec)


async def allow_user_action(
    redis: Redis, user_id: uuid.UUID, action: str, limit: int, window_sec: int
) -> bool:
    """Вариант без исключения — для WebSocket, где ошибку шлём кадром."""
    try:
        await check_user_action(redis, user_id, action, limit, window_sec)
    except AppError:
        return False
    return True
