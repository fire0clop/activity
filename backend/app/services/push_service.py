"""Push-уведомления: iOS — напрямую через APNs, Android — через FCM HTTP v1.

Если провайдер не сконфигурирован — мягко падаем в лог, чтобы dev-окружение
без креденшелов продолжало работать.
"""

import asyncio
import logging
import os
import threading
import uuid

import requests
from google.auth.transport.requests import Request as GoogleAuthRequest
from google.oauth2 import service_account
from sqlalchemy import delete, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.core.config import settings
from app.models.report import DeviceToken

logger = logging.getLogger("push")

# --- APNs (iOS) -----------------------------------------------------------

def apns_enabled() -> bool:
    return bool(
        settings.apns_key_path and os.path.isfile(settings.apns_key_path)
        and settings.apns_key_id and settings.apns_team_id
    )


_apns_client = None
_apns_lock = threading.Lock()


async def _get_apns():
    global _apns_client
    with _apns_lock:
        if _apns_client is None:
            from aioapns import APNs
            _apns_client = APNs(
                key=settings.apns_key_path,
                key_id=settings.apns_key_id,
                team_id=settings.apns_team_id,
                topic=settings.apns_bundle_id,
                use_sandbox=settings.apns_use_sandbox,
            )
        return _apns_client


async def _send_apns(token: str, title: str, body: str, data: dict | None) -> tuple[bool, bool]:
    """Возвращает (ok, token_invalid)."""
    from aioapns import NotificationRequest
    client = await _get_apns()
    message = {"aps": {"alert": {"title": title, "body": body}, "sound": "default"}}
    if data:
        message.update({k: str(v) for k, v in data.items()})
    try:
        resp = await client.send_notification(NotificationRequest(device_token=token, message=message))
    except Exception:  # noqa: BLE001
        logger.exception("[PUSH] APNs send failed")
        return False, False
    if resp.is_successful:
        return True, False
    token_invalid = resp.description in ("BadDeviceToken", "Unregistered", "DeviceTokenNotForTopic")
    logger.warning("[PUSH] APNs error: %s", resp.description)
    return False, token_invalid


# --- FCM (Android) --------------------------------------------------------

_fcm_creds: service_account.Credentials | None = None
_fcm_lock = threading.Lock()
_FCM_SCOPES = ["https://www.googleapis.com/auth/firebase.messaging"]


def fcm_enabled() -> bool:
    return bool(
        settings.fcm_project_id and settings.fcm_credentials_json
        and os.path.isfile(settings.fcm_credentials_json)
    )


def _fcm_token() -> str:
    global _fcm_creds
    with _fcm_lock:
        if _fcm_creds is None:
            _fcm_creds = service_account.Credentials.from_service_account_file(
                settings.fcm_credentials_json, scopes=_FCM_SCOPES)
        if not _fcm_creds.valid:
            _fcm_creds.refresh(GoogleAuthRequest())
        return _fcm_creds.token


def _send_fcm(token: str, title: str, body: str, data: dict | None) -> tuple[bool, bool]:
    url = f"https://fcm.googleapis.com/v1/projects/{settings.fcm_project_id}/messages:send"
    message = {"message": {"token": token, "notification": {"title": title, "body": body},
                           "data": {k: str(v) for k, v in (data or {}).items()}}}
    resp = requests.post(url, json=message, headers={"Authorization": f"Bearer {_fcm_token()}"}, timeout=10)
    if resp.status_code == 200:
        return True, False
    invalid = resp.status_code in (400, 404) and (
        "UNREGISTERED" in resp.text or "INVALID_ARGUMENT" in resp.text
    )
    logger.warning("[PUSH] FCM error %s: %s", resp.status_code, resp.text[:200])
    return False, invalid


# --- Public ---------------------------------------------------------------

async def send_push(db: AsyncSession, user_id: uuid.UUID, title: str, body: str,
                    data: dict | None = None) -> None:
    rows = (
        await db.execute(
            select(DeviceToken.token, DeviceToken.platform).where(DeviceToken.user_id == user_id)
        )
    ).all()
    if not rows:
        return

    invalid: list[str] = []
    for token, platform in rows:
        try:
            if platform == "ios":
                if not apns_enabled():
                    logger.info("[PUSH:stub] ios user=%s title=%r (APNs не сконфигурирован)", user_id, title)
                    continue
                ok, bad = await _send_apns(token, title, body, data)
            else:
                if not fcm_enabled():
                    logger.info("[PUSH:stub] android user=%s title=%r (FCM не сконфигурирован)",
                                user_id, title)
                    continue
                ok, bad = await asyncio.to_thread(_send_fcm, token, title, body, data)
            if bad:
                invalid.append(token)
        except Exception:  # noqa: BLE001 - сбой пуша не должен ронять основной запрос
            logger.exception("[PUSH] send failed")

    if invalid:
        await db.execute(delete(DeviceToken).where(DeviceToken.token.in_(invalid)))
        await db.commit()
