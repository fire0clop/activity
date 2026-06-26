import asyncio
import logging
import secrets

import requests
from redis.asyncio import Redis

from app.core.config import settings
from app.core.exceptions import AppError

logger = logging.getLogger("otp")


def _code_key(phone: str) -> str:
    return f"otp:{phone}"


def _attempts_key(phone: str) -> str:
    return f"otp_attempts:{phone}"


def _cooldown_key(phone: str) -> str:
    return f"otp_cooldown:{phone}"


async def request_code(redis: Redis, phone: str) -> int:
    """Генерирует код, кладёт в Redis, «отправляет» SMS. Возвращает resend_after_sec."""
    if await redis.get(_cooldown_key(phone)):
        ttl = await redis.ttl(_cooldown_key(phone))
        raise AppError(
            "rate_limited",
            "Слишком часто. Повторите позже.",
            429,
            headers={"Retry-After": str(max(ttl, 1))},
        )

    code = "".join(secrets.choice("0123456789") for _ in range(settings.otp_length))
    await redis.set(_code_key(phone), code, ex=settings.otp_ttl_seconds)
    await redis.delete(_attempts_key(phone))
    await redis.set(_cooldown_key(phone), "1", ex=settings.otp_resend_cooldown_sec)

    await _send_sms(phone, code)
    return settings.otp_resend_cooldown_sec


async def _send_sms(phone: str, code: str) -> None:
    """Отправка кода. stub — пишет в лог (dev); smsc — реальная отправка через SMSC.ru."""
    # Код в начале + ключевое слово — так iOS надёжнее предлагает автоподстановку.
    text = f"{code} - kod podtverzhdeniya Skhodka"
    if settings.sms_provider == "stub":
        logger.warning("[OTP] SMS to %s: code=%s", phone, code)
    elif settings.sms_provider == "smsc":
        await asyncio.to_thread(_send_via_smsc, phone, text)
    else:  # pragma: no cover
        raise NotImplementedError(f"SMS provider '{settings.sms_provider}' not implemented")


def _send_via_smsc(phone: str, text: str) -> None:
    """SMSC.ru HTTP API. https://smsc.ru/api/http/  (fmt=3 → JSON-ответ)."""
    params = {
        "login": settings.smsc_login,
        "psw": settings.smsc_password,
        "phones": phone,
        "mes": text,
        "fmt": 3,
        "charset": "utf-8",
    }
    if settings.sms_sender:
        params["sender"] = settings.sms_sender
    try:
        resp = requests.get("https://smsc.ru/sys/send.php", params=params, timeout=10)
        data = resp.json()
    except Exception as exc:  # noqa: BLE001
        logger.exception("[OTP] SMSC request failed")
        raise AppError("sms_send_failed", "Не удалось отправить SMS", 502) from exc

    if "error" in data:
        logger.warning("[OTP] SMSC error %s: %s", data.get("error_code"), data.get("error"))
        raise AppError("sms_send_failed", "Не удалось отправить SMS", 502)
    logger.info("[OTP] SMSC sent id=%s cnt=%s", data.get("id"), data.get("cnt"))


async def verify_code(redis: Redis, phone: str, code: str) -> None:
    """Проверяет код. Бросает AppError при ошибке. При успехе удаляет код."""
    stored = await redis.get(_code_key(phone))
    if stored is None:
        raise AppError("code_expired", "Код устарел, запросите новый", 410)

    attempts = await redis.incr(_attempts_key(phone))
    await redis.expire(_attempts_key(phone), settings.otp_ttl_seconds)
    if attempts > settings.otp_max_attempts:
        await redis.delete(_code_key(phone))
        raise AppError("too_many_attempts", "Слишком много попыток", 429)

    stored_str = stored.decode() if isinstance(stored, bytes) else stored
    if stored_str != code:
        raise AppError("invalid_code", "Код неверный", 400)

    await redis.delete(_code_key(phone))
    await redis.delete(_attempts_key(phone))
