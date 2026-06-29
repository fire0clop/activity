from datetime import UTC, datetime, timedelta

import pytest


def _event_body(**over):
    base = {
        "title": "Теннис",
        "starts_at": (datetime.now(UTC) + timedelta(days=1)).isoformat(),
        "latitude": 55.75,
        "longitude": 37.62,
        "min_participants": 2,
        "max_participants": 3,
        "auto_accept": True,
    }
    base.update(over)
    return base


async def _finished_event_with_guest(client, org, guest):
    """Создаёт событие, добавляет guest как accepted, завершает событие.

    Возвращает event_id.
    """
    ev = (await client.post("/events", headers=org["headers"], json=_event_body())).json()
    eid = ev["id"]
    # auto_accept=True → guest сразу accepted
    join = await client.post(f"/events/{eid}/join", headers=guest["headers"])
    assert join.json()["status"] == "accepted"
    fin = await client.post(f"/events/{eid}/finish", headers=org["headers"])
    assert fin.status_code == 200
    return eid


@pytest.mark.asyncio
async def test_non_participant_cannot_review(client, user_factory) -> None:
    org = await user_factory("Орг")
    guest = await user_factory("Гость")
    outsider = await user_factory("Чужак")
    eid = await _finished_event_with_guest(client, org, guest)

    resp = await client.post(
        f"/events/{eid}/reviews",
        headers=outsider["headers"],
        json={"target_id": guest["id"], "rating": 5},
    )
    assert resp.status_code == 403
    assert resp.json()["error"]["code"] == "forbidden"


@pytest.mark.asyncio
async def test_self_review_rejected(client, user_factory) -> None:
    org = await user_factory("Орг")
    guest = await user_factory("Гость")
    eid = await _finished_event_with_guest(client, org, guest)

    resp = await client.post(
        f"/events/{eid}/reviews",
        headers=org["headers"],
        json={"target_id": org["id"], "rating": 5},
    )
    assert resp.status_code == 403
    assert resp.json()["error"]["code"] == "forbidden"


@pytest.mark.asyncio
async def test_accepted_participant_can_review(client, user_factory) -> None:
    org = await user_factory("Орг")
    guest = await user_factory("Гость")
    eid = await _finished_event_with_guest(client, org, guest)

    # accepted-участник оставляет отзыв организатору
    resp = await client.post(
        f"/events/{eid}/reviews",
        headers=guest["headers"],
        json={"target_id": org["id"], "rating": 4, "comment": "Отлично"},
    )
    assert resp.status_code == 201
    body = resp.json()
    assert body["rating"] == 4
    assert body["target_id"] == org["id"]
    assert body["author"]["id"] == guest["id"]

    # отзыв виден в списке отзывов организатора
    listed = (
        await client.get(f"/users/{org['id']}/reviews", headers=guest["headers"])
    ).json()["items"]
    assert any(r["author"]["id"] == guest["id"] and r["rating"] == 4 for r in listed)

    # организатор тоже участник → может оставить отзыв гостю
    org_resp = await client.post(
        f"/events/{eid}/reviews",
        headers=org["headers"],
        json={"target_id": guest["id"], "rating": 5},
    )
    assert org_resp.status_code == 201
