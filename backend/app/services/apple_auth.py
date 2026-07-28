"""Проверка Apple identity token (Sign in with Apple).

Токен — JWT, подписанный Apple (RS256). Проверяем подпись публичными ключами Apple
(JWKS, кешируются на час), issuer, audience (bundle id) и срок. Возвращаем (apple_user_id, email).
"""

import logging
import time

import requests
from jose import jwt
from jose.exceptions import JWTError

from app.core.config import settings
from app.core.exceptions import AppError

logger = logging.getLogger("apple")

_APPLE_ISSUER = "https://appleid.apple.com"
_APPLE_KEYS_URL = "https://appleid.apple.com/auth/keys"
_KEYS_TTL_SEC = 3600
_keys_cache: dict = {"keys": None, "fetched_at": 0.0}


def _apple_keys() -> list[dict]:
    now = time.time()
    if _keys_cache["keys"] is None or now - _keys_cache["fetched_at"] > _KEYS_TTL_SEC:
        resp = requests.get(_APPLE_KEYS_URL, timeout=10)
        resp.raise_for_status()
        _keys_cache["keys"] = resp.json()["keys"]
        _keys_cache["fetched_at"] = now
    return _keys_cache["keys"]


def verify_identity_token(identity_token: str) -> tuple[str, str | None]:
    """Проверяет Apple identity token. Возвращает (apple_user_id, email|None).

    Бросает AppError(401), если токен невалиден (подпись/issuer/audience/срок)."""
    try:
        header = jwt.get_unverified_header(identity_token)
        key = next((k for k in _apple_keys() if k["kid"] == header.get("kid")), None)
        if key is None:
            raise AppError("apple_auth_failed", "Не удалось проверить вход через Apple", 401)
        payload = jwt.decode(
            identity_token,
            key,
            algorithms=["RS256"],
            audience=settings.apple_client_id,
            issuer=_APPLE_ISSUER,
        )
    except (JWTError, KeyError, requests.RequestException) as exc:
        logger.warning("apple: token verification failed: %s", exc)
        raise AppError("apple_auth_failed", "Не удалось проверить вход через Apple", 401) from exc
    return payload["sub"], payload.get("email")
