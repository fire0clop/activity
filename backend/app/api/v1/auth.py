import uuid
from datetime import UTC, datetime

from fastapi import APIRouter, Request, status
from sqlalchemy import select, update

from app.core.config import settings
from app.core.deps import DbSession, RedisDep
from app.core.exceptions import AppError, conflict, not_found, unauthorized
from app.core.security import (
    create_access_token,
    create_refresh_token,
    decode_token,
    hash_password,
    hash_token,
    verify_password,
)
from app.models.user import RefreshToken, User
from app.schemas.auth import (
    LoginIn,
    LogoutIn,
    RefreshIn,
    RegisterIn,
    RegisterOut,
    RequestCodeIn,
    RequestCodeOut,
    ResetPasswordIn,
    TokenPair,
)
from app.services import otp_service

router = APIRouter(prefix="/auth", tags=["auth"])

# Брутфорс-защита логина: не более N неудачных попыток на телефон за окно.
LOGIN_MAX_FAILS = 10
LOGIN_FAIL_WINDOW_SEC = 15 * 60


def _login_fail_key(phone: str) -> str:
    return f"login_fail:{phone}"


async def _check_login_throttle(redis: RedisDep, phone: str) -> None:
    key = _login_fail_key(phone)
    fails = await redis.get(key)
    if fails is not None and int(fails) >= LOGIN_MAX_FAILS:
        ttl = await redis.ttl(key)
        raise AppError(
            "rate_limited",
            "Слишком много неудачных попыток входа. Повторите позже.",
            429,
            headers={"Retry-After": str(max(ttl, 1))},
        )


async def _register_login_fail(redis: RedisDep, phone: str) -> None:
    key = _login_fail_key(phone)
    fails = await redis.incr(key)
    if fails == 1:
        await redis.expire(key, LOGIN_FAIL_WINDOW_SEC)


async def _issue_pair(db: DbSession, user_id: uuid.UUID) -> TokenPair:
    access, expires_in = create_access_token(user_id)
    refresh, _jti, expires_at = create_refresh_token(user_id)
    db.add(
        RefreshToken(
            user_id=user_id,
            token_hash=hash_token(refresh),
            expires_at=expires_at,
            created_at=datetime.now(UTC),
        )
    )
    await db.commit()
    return TokenPair(access_token=access, refresh_token=refresh, expires_in=expires_in)


async def _revoke_all(db: DbSession, user_id: uuid.UUID) -> None:
    await db.execute(
        update(RefreshToken).where(RefreshToken.user_id == user_id, RefreshToken.revoked.is_(False))
        .values(revoked=True)
    )


async def _check_request_code_ip_limit(redis: RedisDep, request: Request) -> None:
    """Ограничивает число запросов кода с одного IP в час (анти-SMS-бомбинг).

    При недоступном Redis — пропускаем (деградация в сторону доступности, как и общий лимит)."""
    limit = settings.otp_request_ip_per_hour
    if not settings.rate_limit_enabled or limit <= 0:
        return
    ip = request.client.host if request.client else "unknown"
    window = int(datetime.now(UTC).timestamp() // 3600)
    key = f"otp_ip:{ip}:{window}"
    try:
        count = await redis.incr(key)
        if count == 1:
            await redis.expire(key, 3600)
    except Exception:  # noqa: BLE001 - Redis недоступен → не блокируем
        return
    if count > limit:
        raise AppError(
            "rate_limited",
            "Слишком много запросов кода. Повторите позже.",
            429,
            headers={"Retry-After": "3600"},
        )


@router.post("/request-code", response_model=RequestCodeOut)
async def request_code(body: RequestCodeIn, redis: RedisDep, request: Request) -> RequestCodeOut:
    """Отправляет SMS-код. Используется при регистрации и смене пароля."""
    await _check_request_code_ip_limit(redis, request)
    resend_after = await otp_service.request_code(redis, body.phone)
    return RequestCodeOut(sent=True, resend_after_sec=resend_after)


@router.post("/register", response_model=RegisterOut)
async def register(body: RegisterIn, db: DbSession, redis: RedisDep) -> RegisterOut:
    """Регистрация: подтверждаем телефон кодом из SMS и задаём пароль."""
    await otp_service.verify_code(redis, body.phone, body.code)

    user = (await db.execute(select(User).where(User.phone == body.phone))).scalar_one_or_none()
    is_new_user = user is None
    if user is not None and user.password_hash:
        raise conflict("already_registered", "Этот номер уже зарегистрирован — войдите по паролю")
    if user is None:
        user = User(phone=body.phone, is_phone_verified=True)
        db.add(user)
    user.password_hash = hash_password(body.password)
    user.is_phone_verified = True
    # Фиксируем принятие правил/политики на момент регистрации (App Store 1.2 для UGC).
    user.tos_accepted_version = settings.tos_version
    await db.flush()

    pair = await _issue_pair(db, user.id)
    return RegisterOut(**pair.model_dump(), is_new_user=is_new_user)


@router.post("/login", response_model=TokenPair)
async def login(body: LoginIn, db: DbSession, redis: RedisDep) -> TokenPair:
    """Вход по телефону и паролю (без SMS)."""
    await _check_login_throttle(redis, body.phone)
    user = (await db.execute(select(User).where(User.phone == body.phone))).scalar_one_or_none()
    if user is None or not user.password_hash or not verify_password(body.password, user.password_hash):
        await _register_login_fail(redis, body.phone)
        raise AppError("invalid_credentials", "Неверный телефон или пароль", 401)
    await redis.delete(_login_fail_key(body.phone))  # сброс счётчика при успехе
    return await _issue_pair(db, user.id)


@router.post("/reset-password", response_model=TokenPair)
async def reset_password(body: ResetPasswordIn, db: DbSession, redis: RedisDep) -> TokenPair:
    """Смена пароля с подтверждением по SMS. Сбрасывает все старые сессии."""
    await otp_service.verify_code(redis, body.phone, body.code)
    user = (await db.execute(select(User).where(User.phone == body.phone))).scalar_one_or_none()
    if user is None:
        raise not_found("Пользователь не найден")
    user.password_hash = hash_password(body.new_password)
    await _revoke_all(db, user.id)
    await db.flush()
    return await _issue_pair(db, user.id)


@router.post("/refresh", response_model=TokenPair)
async def refresh(body: RefreshIn, db: DbSession) -> TokenPair:
    payload = decode_token(body.refresh_token, expected_type="refresh")
    user_id = uuid.UUID(payload["sub"])

    token_hash = hash_token(body.refresh_token)
    result = await db.execute(select(RefreshToken).where(RefreshToken.token_hash == token_hash))
    stored = result.scalar_one_or_none()
    if stored is None or stored.revoked or stored.expires_at < datetime.now(UTC):
        raise unauthorized("Refresh-токен недействителен")

    stored.revoked = True
    return await _issue_pair(db, user_id)


@router.post("/logout", status_code=status.HTTP_204_NO_CONTENT)
async def logout(body: LogoutIn, db: DbSession) -> None:
    token_hash = hash_token(body.refresh_token)
    result = await db.execute(select(RefreshToken).where(RefreshToken.token_hash == token_hash))
    stored = result.scalar_one_or_none()
    if stored is not None:
        stored.revoked = True
        await db.commit()
