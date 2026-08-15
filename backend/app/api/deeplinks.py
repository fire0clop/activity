"""Универсальные ссылки: событие открывается прямо в приложении.

Три части:
  1. `/.well-known/apple-app-site-association` — файл, по которому iOS понимает, что
     домен принадлежит приложению, и начинает перехватывать ссылки `/e/<id>`.
  2. `/e/{event_id}` — то, что видит браузер. Никакой карточки события здесь нет:
     страница публично ничего не рассказывает, только уводит в App Store.
  3. Отложенный переход. App Store не передаёт исходную ссылку свежепоставленному
     приложению, поэтому клик запоминается на короткое время, а приложение на первом
     запуске спрашивает: «был ли отсюда недавно переход?». Совпадение ищем по IP и
     User-Agent — за общим NAT возможны осечки, поэтому ссылка ведёт на конкретное
     событие и без этого механизма: достаточно нажать её ещё раз.
"""

import logging
from datetime import UTC, datetime

from fastapi import APIRouter, Request
from fastapi.responses import JSONResponse, RedirectResponse

from app.core.config import settings
from app.core.deps import CurrentUser, RedisDep

logger = logging.getLogger("deeplinks")

router = APIRouter(tags=["deeplinks"])

# Клик живёт недолго: столько, сколько занимает установка приложения из App Store.
CLICK_TTL_SEC = 1800


def _click_key(ip: str, ua: str) -> str:
    # UA целиком в ключ не кладём — только его отпечаток фиксированной длины.
    return f"deeplink:click:{ip}:{hash(ua) & 0xFFFFFFFF:08x}"


@router.get("/.well-known/apple-app-site-association", include_in_schema=False)
async def apple_app_site_association() -> JSONResponse:
    """Связь домена с приложением. Отдаётся как JSON, без редиректов — так требует iOS."""
    if not settings.apple_team_id:
        # Apple кэширует этот файл надолго: лучше честная ошибка, чем битый appID,
        # который потом придётся ждать, пока протухнет.
        logger.error("APNS_TEAM_ID не задан — apple-app-site-association не отдаём")
        return JSONResponse(
            {"error": "team id is not configured"}, status_code=503,
            media_type="application/json",
        )
    return JSONResponse(
        {
            "applinks": {
                "details": [
                    {
                        "appIDs": [f"{settings.apple_team_id}.{settings.apple_bundle_id}"],
                        "components": [
                            {"/": "/e/*", "comment": "Карточка события"},
                        ],
                    }
                ]
            }
        },
        media_type="application/json",
    )


@router.get("/e/{event_id}", include_in_schema=False)
async def open_event(event_id: str, request: Request, redis: RedisDep) -> RedirectResponse:
    """Браузерная развилка: приложение установлено — сюда не дойдёт, иначе App Store."""
    ip = request.headers.get("x-forwarded-for", "").split(",")[0].strip() or (
        request.client.host if request.client else "unknown"
    )
    ua = request.headers.get("user-agent", "")
    try:
        await redis.setex(_click_key(ip, ua), CLICK_TTL_SEC, event_id)
    except Exception:  # noqa: BLE001 - потеря отложенного перехода не должна ломать редирект
        logger.warning("не удалось запомнить переход по ссылке", exc_info=True)
    return RedirectResponse(settings.app_store_url, status_code=302)


@router.get("/api/v1/deeplinks/pending", include_in_schema=False)
async def pending_deeplink(_: CurrentUser, request: Request, redis: RedisDep) -> dict:
    """Приложение спрашивает после установки: «меня открыли по ссылке на событие?».

    Ответ одноразовый: найденный переход сразу забывается, чтобы он не сработал дважды.
    """
    ip = request.headers.get("x-forwarded-for", "").split(",")[0].strip() or (
        request.client.host if request.client else "unknown"
    )
    ua = request.headers.get("user-agent", "")
    try:
        key = _click_key(ip, ua)
        event_id = await redis.get(key)
        if event_id:
            await redis.delete(key)
            return {"event_id": event_id, "matched_at": datetime.now(UTC).isoformat()}
    except Exception:  # noqa: BLE001
        logger.warning("не удалось прочитать отложенный переход", exc_info=True)
    return {"event_id": None}
