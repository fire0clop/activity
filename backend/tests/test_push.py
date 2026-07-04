"""Push-триггеры: заявка → организатору, решение → участнику; чистка мёртвых токенов.

APNs мокается на уровне push_service (реальные креды в тестах не нужны).
"""

from datetime import UTC, datetime, timedelta

import pytest
from sqlalchemy import select

from app.db.session import SessionLocal
from app.models.report import DeviceToken
from app.services import push_service


def _body(**over):
    base = {
        "title": "Теннис",
        "starts_at": (datetime.now(UTC) + timedelta(days=1)).isoformat(),
        "latitude": 55.75,
        "longitude": 37.62,
        "min_participants": 2,
        "max_participants": 2,
        "auto_accept": False,
    }
    base.update(over)
    return base


@pytest.fixture
def apns_recorder(monkeypatch):
    """Включает APNs и подменяет отправку на запись вызовов."""
    sent: list[dict] = []

    async def fake_send(token, title, body, data):
        sent.append({"token": token, "title": title, "body": body, "data": data})
        return True, False

    monkeypatch.setattr(push_service, "apns_enabled", lambda: True)
    monkeypatch.setattr(push_service, "_send_apns", fake_send)
    return sent


@pytest.mark.asyncio
async def test_join_and_decision_trigger_pushes(client, user_factory, apns_recorder) -> None:
    org = await user_factory("Орг")
    guest = await user_factory("Гость")
    await client.post("/devices", headers=org["headers"],
                      json={"token": "tok-org", "platform": "ios"})
    await client.post("/devices", headers=guest["headers"],
                      json={"token": "tok-guest", "platform": "ios"})

    eid = (await client.post("/events", headers=org["headers"], json=_body())).json()["id"]

    # заявка → пуш организатору
    await client.post(f"/events/{eid}/join", headers=guest["headers"])
    assert any(p["token"] == "tok-org" and p["title"] == "Новая заявка" for p in apns_recorder)

    # принятие → пуш участнику с раскрытым временем
    pid = (await client.get(f"/events/{eid}/participants", headers=org["headers"],
                            params={"status": "pending"})).json()["items"][0]["participation_id"]
    await client.post(f"/participations/{pid}/accept", headers=org["headers"])
    accepted = [p for p in apns_recorder if p["token"] == "tok-guest"]
    assert accepted and accepted[-1]["title"] == "Заявка принята"
    assert accepted[-1]["data"]["event_id"] == eid


@pytest.mark.asyncio
async def test_reject_triggers_push(client, user_factory, apns_recorder) -> None:
    org = await user_factory("Орг")
    guest = await user_factory("Гость")
    await client.post("/devices", headers=guest["headers"],
                      json={"token": "tok-guest", "platform": "ios"})
    eid = (await client.post("/events", headers=org["headers"], json=_body())).json()["id"]
    await client.post(f"/events/{eid}/join", headers=guest["headers"])
    pid = (await client.get(f"/events/{eid}/participants", headers=org["headers"],
                            params={"status": "pending"})).json()["items"][0]["participation_id"]
    await client.post(f"/participations/{pid}/reject", headers=org["headers"])
    assert any(p["title"] == "Заявка отклонена" for p in apns_recorder)


@pytest.mark.asyncio
async def test_chat_message_pushes_offline_members(client, user_factory, apns_recorder) -> None:
    org = await user_factory("Орг")
    guest = await user_factory("Гость")
    await client.post("/devices", headers=guest["headers"],
                      json={"token": "tok-guest", "platform": "ios"})
    eid = (await client.post("/events", headers=org["headers"],
                             json=_body(auto_accept=True, max_participants=3))).json()["id"]
    await client.post(f"/events/{eid}/join", headers=guest["headers"])
    cid = (await client.get(f"/events/{eid}", headers=org["headers"])).json()["conversation_id"]

    import uuid as _uuid

    from app.db.session import SessionLocal as SL
    from app.services import chat_service
    async with SL() as db:
        await chat_service.post_message(
            db, _uuid.UUID(cid), "Привет!", sender_id=_uuid.UUID(org["id"]))

    got = [p for p in apns_recorder if p["token"] == "tok-guest"
           and p["data"].get("conversation_id") == cid]
    assert got and "Привет!" in got[-1]["body"]


@pytest.mark.asyncio
async def test_invalid_token_pruned(client, user_factory, monkeypatch) -> None:
    async def dead_token(token, title, body, data):
        return False, True  # (ok, token_invalid)

    monkeypatch.setattr(push_service, "apns_enabled", lambda: True)
    monkeypatch.setattr(push_service, "_send_apns", dead_token)

    org = await user_factory("Орг")
    guest = await user_factory("Гость")
    await client.post("/devices", headers=org["headers"],
                      json={"token": "tok-dead", "platform": "ios"})
    eid = (await client.post("/events", headers=org["headers"], json=_body())).json()["id"]
    await client.post(f"/events/{eid}/join", headers=guest["headers"])

    async with SessionLocal() as db:
        left = (await db.execute(
            select(DeviceToken).where(DeviceToken.token == "tok-dead"))).scalars().all()
    assert left == []
