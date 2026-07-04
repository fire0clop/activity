"""SMS-провайдеры (Twilio/SMSC): формирование запроса и обработка ошибок API.

HTTP мокается — реальные крединшелы не нужны.
"""

import pytest

from app.core.config import Settings, settings
from app.core.exceptions import AppError
from app.services import otp_service


class _Resp:
    def __init__(self, status_code: int, payload: dict):
        self.status_code = status_code
        self._payload = payload

    def json(self) -> dict:
        return self._payload


@pytest.fixture
def twilio_creds():
    saved = (settings.twilio_account_sid, settings.twilio_auth_token, settings.twilio_from)
    settings.twilio_account_sid = "AC_test"
    settings.twilio_auth_token = "secret"
    settings.twilio_from = "+15005550006"
    yield
    (settings.twilio_account_sid, settings.twilio_auth_token, settings.twilio_from) = saved


def test_twilio_sends_with_basic_auth(monkeypatch, twilio_creds) -> None:
    calls: list[dict] = []

    def fake_post(url, data=None, auth=None, timeout=None):
        calls.append({"url": url, "data": data, "auth": auth})
        return _Resp(201, {"sid": "SM123", "status": "queued"})

    monkeypatch.setattr(otp_service.requests, "post", fake_post)
    otp_service._send_via_twilio("+79991234567", "1234 - kod")

    assert len(calls) == 1
    call = calls[0]
    assert "AC_test/Messages.json" in call["url"]
    assert call["auth"] == ("AC_test", "secret")
    assert call["data"] == {"To": "+79991234567", "From": "+15005550006", "Body": "1234 - kod"}


def test_twilio_api_error_raises_sms_send_failed(monkeypatch, twilio_creds) -> None:
    monkeypatch.setattr(
        otp_service.requests, "post",
        lambda *a, **kw: _Resp(400, {"code": 21211, "message": "Invalid 'To'"}),
    )
    with pytest.raises(AppError) as e:
        otp_service._send_via_twilio("+7999", "x")
    assert e.value.code == "sms_send_failed"
    assert e.value.status_code == 502


def test_twilio_network_error_raises_sms_send_failed(monkeypatch, twilio_creds) -> None:
    def boom(*a, **kw):
        raise OSError("connection refused")

    monkeypatch.setattr(otp_service.requests, "post", boom)
    with pytest.raises(AppError) as e:
        otp_service._send_via_twilio("+7999", "x")
    assert e.value.code == "sms_send_failed"


def test_smsc_error_raises_sms_send_failed(monkeypatch) -> None:
    monkeypatch.setattr(
        otp_service.requests, "get",
        lambda *a, **kw: _Resp(200, {"error": "invalid login", "error_code": 2}),
    )
    with pytest.raises(AppError) as e:
        otp_service._send_via_smsc("+7999", "x")
    assert e.value.code == "sms_send_failed"


def test_prod_config_rejects_stub_and_incomplete_providers() -> None:
    base = dict(
        app_env="production",
        app_secret_key="x" * 40,
        cors_origins="https://app.example",
        auto_create_tables=False,
        # явно пустые креды: контейнерное окружение не должно влиять на тест
        smsc_login="", smsc_password="",
        twilio_account_sid="", twilio_auth_token="", twilio_from="",
    )
    with pytest.raises(RuntimeError, match="SMS_PROVIDER=stub"):
        Settings(**base, sms_provider="stub").validate_for_prod()
    with pytest.raises(RuntimeError, match="TWILIO"):
        Settings(**base, sms_provider="twilio").validate_for_prod()
    with pytest.raises(RuntimeError, match="SMSC"):
        Settings(**base, sms_provider="smsc").validate_for_prod()
    # полный конфиг — валиден
    ok = {**base, "twilio_account_sid": "AC", "twilio_auth_token": "t",
          "twilio_from": "+1500"}
    Settings(**ok, sms_provider="twilio").validate_for_prod()
