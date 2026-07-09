"""WebSocket-чат: подключение, история, доставка, presence, архив, rate-limit.

Тесты синхронные — starlette TestClient гоняет ASGI-приложение (с lifespan:
Redis pub/sub менеджер запущен) в своём портале; REST-подготовка через него же.
"""

import uuid
from datetime import UTC, datetime, timedelta

import pytest
import redis as sync_redis
from starlette.testclient import TestClient
from starlette.websockets import WebSocketDisconnect

from app.core.config import settings
from app.main import app

_PNG = (
    b"\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR\x00\x00\x00\x01\x00\x00\x00\x01\x08\x06"
    b"\x00\x00\x00\x1f\x15\xc4\x89\x00\x00\x00\nIDATx\x9cc\x00\x01\x00\x00\x05"
    b"\x00\x01\r\n-\xb4\x00\x00\x00\x00IEND\xaeB`\x82"
)
API = "/api/v1"


def _make_user(tc: TestClient, name: str) -> dict:
    phone = "+7999" + f"{uuid.uuid4().int % 10_000_000:07d}"
    tc.post(f"{API}/auth/request-code", json={"phone": phone})
    r = sync_redis.Redis.from_url(settings.redis_url)
    code = r.get(f"otp:{phone}").decode()
    r.close()
    vt = tc.post(f"{API}/auth/verify-code", json={"phone": phone, "code": code}).json()["verification_token"]
    token = tc.post(
        f"{API}/auth/register",
        json={"verification_token": vt, "password": "secret123"},
    ).json()["access_token"]
    h = {"Authorization": f"Bearer {token}"}
    tc.patch(f"{API}/users/me", headers=h, json={"name": name, "bio": "тест"})
    tc.post(f"{API}/users/me/avatar", headers=h, files={"file": ("a.png", _PNG, "image/png")})
    return {"token": token, "headers": h}


def _make_conversation(tc: TestClient) -> tuple[dict, dict, str, str]:
    """Организатор + принятый гость + event id + conversation id."""
    org = _make_user(tc, "Орг")
    guest = _make_user(tc, "Гость")
    eid = tc.post(
        f"{API}/events", headers=org["headers"],
        json={
            "title": "Теннис",
            "starts_at": (datetime.now(UTC) + timedelta(days=1)).isoformat(),
            "latitude": 55.75, "longitude": 37.62,
            "min_participants": 2, "max_participants": 3,
            "auto_accept": True,
        },
    ).json()["id"]
    assert tc.post(f"{API}/events/{eid}/join", headers=guest["headers"]).json()["status"] == "accepted"
    cid = tc.get(f"{API}/events/{eid}", headers=org["headers"]).json()["conversation_id"]
    assert cid
    return org, guest, eid, cid


def _recv_type(ws, wanted: str, max_frames: int = 15) -> dict:
    """Читает кадры, пропуская нерелевантные (presence/typing), до нужного типа."""
    for _ in range(max_frames):
        frame = ws.receive_json()
        if frame["type"] == wanted:
            return frame
    raise AssertionError(f"не дождались кадра {wanted!r}")


def _ws_url(cid: str, token: str) -> str:
    return f"{API}/ws/chat/{cid}?token={token}"


def test_ws_history_and_message_delivery() -> None:
    with TestClient(app) as tc:
        org, guest, _, cid = _make_conversation(tc)
        with tc.websocket_connect(_ws_url(cid, org["token"])) as ws1:
            history = _recv_type(ws1, "history")
            # системные сообщения о вступлении и времени уже в истории
            assert any("в группе" in m["text"] for m in history["messages"])

            with tc.websocket_connect(_ws_url(cid, guest["token"])) as ws2:
                _recv_type(ws2, "history")
                ws1.send_json({"type": "message", "text": "Привет!"})
                got1 = _recv_type(ws1, "message")
                got2 = _recv_type(ws2, "message")
                assert got1["message"]["text"] == "Привет!"
                assert got2["message"]["text"] == "Привет!"
                assert got2["message"]["sender"]["name"] == "Орг"


def test_ws_presence_updates() -> None:
    with TestClient(app) as tc:
        org, guest, _, cid = _make_conversation(tc)
        with tc.websocket_connect(_ws_url(cid, org["token"])) as ws1:
            _recv_type(ws1, "history")
            p1 = _recv_type(ws1, "presence")
            assert len(p1["online_user_ids"]) == 1
            with tc.websocket_connect(_ws_url(cid, guest["token"])) as ws2:
                _recv_type(ws2, "history")
                p2 = _recv_type(ws1, "presence")
                assert len(p2["online_user_ids"]) == 2


def test_ws_rejects_bad_token_and_non_member() -> None:
    with TestClient(app) as tc:
        _, _, _, cid = _make_conversation(tc)
        with pytest.raises(WebSocketDisconnect) as e1:
            with tc.websocket_connect(_ws_url(cid, "garbage")):
                pass
        assert e1.value.code == 4401

        outsider = _make_user(tc, "Чужой")
        with pytest.raises(WebSocketDisconnect) as e2:
            with tc.websocket_connect(_ws_url(cid, outsider["token"])):
                pass
        assert e2.value.code == 4403


def test_ws_archived_conversation_is_readonly() -> None:
    with TestClient(app) as tc:
        org, _, eid, cid = _make_conversation(tc)
        tc.post(f"{API}/events/{eid}/finish", headers=org["headers"])
        with tc.websocket_connect(_ws_url(cid, org["token"])) as ws:
            _recv_type(ws, "history")
            ws.send_json({"type": "message", "text": "после архива"})
            err = _recv_type(ws, "error")
            assert err["code"] == "forbidden"


def test_ws_message_rate_limited() -> None:
    saved = settings.user_rl_messages_per_min
    settings.user_rl_messages_per_min = 2
    try:
        with TestClient(app) as tc:
            org, _, _, cid = _make_conversation(tc)
            with tc.websocket_connect(_ws_url(cid, org["token"])) as ws:
                _recv_type(ws, "history")
                ws.send_json({"type": "message", "text": "раз"})
                _recv_type(ws, "message")
                ws.send_json({"type": "message", "text": "два"})
                _recv_type(ws, "message")
                ws.send_json({"type": "message", "text": "три"})
                err = _recv_type(ws, "error")
                assert err["code"] == "rate_limited"
    finally:
        settings.user_rl_messages_per_min = saved
