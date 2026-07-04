import logging
import time
import uuid

from starlette.middleware.base import BaseHTTPMiddleware
from starlette.requests import Request
from starlette.responses import JSONResponse, Response

from app.core.config import settings
from app.core.logging import request_id_ctx

logger = logging.getLogger("access")


class RequestContextMiddleware(BaseHTTPMiddleware):
    """Присваивает request_id, пишет структурный access-лог, добавляет заголовок X-Request-ID."""

    async def dispatch(self, request: Request, call_next) -> Response:
        rid = request.headers.get("X-Request-ID") or uuid.uuid4().hex
        token = request_id_ctx.set(rid)
        start = time.perf_counter()
        try:
            response = await call_next(request)
        finally:
            duration_ms = round((time.perf_counter() - start) * 1000, 1)
            status = locals().get("response").status_code if "response" in locals() else 500
            logger.info(
                "request",
                extra={
                    "method": request.method,
                    "path": request.url.path,
                    "status": status,
                    "duration_ms": duration_ms,
                    "client": request.client.host if request.client else "-",
                },
            )
            request_id_ctx.reset(token)
        response.headers["X-Request-ID"] = rid
        return response


class RateLimitMiddleware(BaseHTTPMiddleware):
    """Грубый rate-limit на IP (фиксированное окно в Redis). Защита от всплесков/перебора.

    Тонкие лимиты (например, на OTP) живут в своих сервисах. Здесь — общий потолок.
    """

    async def dispatch(self, request: Request, call_next) -> Response:
        if not settings.rate_limit_enabled or request.url.path.endswith("/health"):
            return await call_next(request)

        redis = getattr(request.app.state, "redis", None)
        if redis is None:
            return await call_next(request)

        ip = request.client.host if request.client else "unknown"
        window = int(time.time() // 60)
        key = f"rl:{ip}:{window}"
        try:
            count = await redis.incr(key)
            if count == 1:
                await redis.expire(key, 60)
        except Exception:  # noqa: BLE001 - Redis недоступен → не блокируем трафик
            logger.warning("rate limit: Redis unavailable, request passed unthrottled", exc_info=True)
            return await call_next(request)

        if count > settings.rate_limit_per_min:
            return JSONResponse(
                status_code=429,
                content={"error": {"code": "rate_limited",
                                   "message": "Слишком много запросов", "details": {}}},
                headers={"Retry-After": "60"},
            )
        return await call_next(request)
