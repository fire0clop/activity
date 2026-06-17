import hashlib
import uuid
from datetime import UTC, datetime, timedelta

import bcrypt
from jose import JWTError, jwt

from app.core.config import settings
from app.core.exceptions import unauthorized


def _now() -> datetime:
    return datetime.now(UTC)


def create_access_token(user_id: uuid.UUID) -> tuple[str, int]:
    """Возвращает (token, expires_in_seconds)."""
    expires_in = settings.access_token_ttl_min * 60
    payload = {
        "sub": str(user_id),
        "type": "access",
        "iat": int(_now().timestamp()),
        "exp": int((_now() + timedelta(seconds=expires_in)).timestamp()),
    }
    token = jwt.encode(payload, settings.app_secret_key, algorithm=settings.jwt_alg)
    return token, expires_in


def create_refresh_token(user_id: uuid.UUID) -> tuple[str, str, datetime]:
    """Возвращает (token, jti, expires_at)."""
    jti = str(uuid.uuid4())
    expires_at = _now() + timedelta(days=settings.refresh_token_ttl_days)
    payload = {
        "sub": str(user_id),
        "type": "refresh",
        "jti": jti,
        "iat": int(_now().timestamp()),
        "exp": int(expires_at.timestamp()),
    }
    token = jwt.encode(payload, settings.app_secret_key, algorithm=settings.jwt_alg)
    return token, jti, expires_at


def decode_token(token: str, expected_type: str) -> dict:
    try:
        payload = jwt.decode(token, settings.app_secret_key, algorithms=[settings.jwt_alg])
    except JWTError:
        raise unauthorized("Невалидный или просроченный токен") from None
    if payload.get("type") != expected_type:
        raise unauthorized("Неверный тип токена")
    return payload


def hash_token(token: str) -> str:
    """Хеш refresh-токена для хранения в БД (токены высокоэнтропийны → sha256 достаточно)."""
    return hashlib.sha256(token.encode()).hexdigest()


def hash_password(password: str) -> str:
    return bcrypt.hashpw(password.encode("utf-8"), bcrypt.gensalt()).decode("utf-8")


def verify_password(password: str, hashed: str) -> bool:
    try:
        return bcrypt.checkpw(password.encode("utf-8"), hashed.encode("utf-8"))
    except ValueError:
        return False
