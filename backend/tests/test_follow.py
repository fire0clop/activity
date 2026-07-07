"""Подписка на организатора: follow/unfollow/status и пуш о любом новом событии автора."""

from datetime import UTC, datetime, timedelta

import pytest

from app.services import push_service


def _event_body(**over):
    base = {
        "title": "Событие", "category": "sport",
        "starts_at": (datetime.now(UTC) + timedelta(days=1)).isoformat(),
        "latitude": 55.75, "longitude": 37.62,
        "min_participants": 2, "max_participants": 5, "auto_accept": True,
    }
    base.update(over)
    return base


@pytest.fixture
def apns_recorder(monkeypatch):
    sent: list[dict] = []

    async def fake_send(token, title, body, data):
        sent.append({"token": token, "title": title, "body": body, "data": data})
        return True, False

    monkeypatch.setattr(push_service, "apns_enabled", lambda: True)
    monkeypatch.setattr(push_service, "_send_apns", fake_send)
    return sent


@pytest.mark.asyncio
async def test_follow_status_and_idempotency(client, user_factory) -> None:
    me = await user_factory("Я")
    org = await user_factory("Орг")

    # на себя подписаться нельзя
    assert (await client.post(f"/users/{me['id']}/follow", headers=me["headers"])).status_code == 422

    assert (await client.post(f"/users/{org['id']}/follow", headers=me["headers"])).status_code == 204
    assert (await client.get(f"/users/{org['id']}/follow-status",
                             headers=me["headers"])).json()["following"] is True
    # повторный follow идемпотентен
    assert (await client.post(f"/users/{org['id']}/follow", headers=me["headers"])).status_code == 204

    # follow'ы не засоряют обычный список подписок
    assert (await client.get("/subscriptions", headers=me["headers"])).json()["items"] == []

    assert (await client.delete(f"/users/{org['id']}/follow", headers=me["headers"])).status_code == 204
    assert (await client.get(f"/users/{org['id']}/follow-status",
                             headers=me["headers"])).json()["following"] is False


@pytest.mark.asyncio
async def test_followed_organizer_new_event_notifies(client, user_factory, apns_recorder) -> None:
    org = await user_factory("Орг")
    fan = await user_factory("Фанат")
    await client.post("/devices", headers=fan["headers"], json={"token": "tok-fan", "platform": "ios"})
    await client.post(f"/users/{org['id']}/follow", headers=fan["headers"])

    # Событие в категории, на которую фанат НЕ подписан по критериям — он получит пуш
    # именно потому, что подписан на организатора.
    eid = (await client.post("/events", headers=org["headers"],
                             json=_event_body(category="music"))).json()["id"]

    got = [p for p in apns_recorder if p["token"] == "tok-fan"]
    assert got and got[-1]["data"]["event_id"] == eid
