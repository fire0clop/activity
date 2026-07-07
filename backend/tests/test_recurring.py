"""Повторяющиеся события: при завершении weekly-события создаётся следующее вхождение."""

from datetime import UTC, datetime, timedelta

import pytest


def _event_body(**over):
    base = {
        "title": "Повтор", "category": "sport",
        "starts_at": (datetime.now(UTC) + timedelta(days=2)).isoformat(),
        "latitude": 55.75, "longitude": 37.62,
        "min_participants": 2, "max_participants": 5, "auto_accept": True,
    }
    base.update(over)
    return base


async def _mine_titled(client, headers, title: str) -> list[dict]:
    items = (await client.get("/events/mine", headers=headers)).json()["items"]
    return [e for e in items if e["title"] == title]


@pytest.mark.asyncio
async def test_weekly_event_clones_on_finish(client, user_factory) -> None:
    org = await user_factory("Орг")
    eid = (await client.post("/events", headers=org["headers"],
                             json=_event_body(recurrence="weekly"))).json()["id"]

    await client.post(f"/events/{eid}/finish", headers=org["headers"])

    events = await _mine_titled(client, org["headers"], "Повтор")
    # исходное (finished) + следующее вхождение (open)
    assert len(events) == 2
    statuses = sorted(e["status"] for e in events)
    assert statuses == ["finished", "open"]

    # Повторный finish не должен плодить ещё один клон.
    await client.post(f"/events/{eid}/finish", headers=org["headers"])
    assert len(await _mine_titled(client, org["headers"], "Повтор")) == 2


@pytest.mark.asyncio
async def test_non_recurring_does_not_clone(client, user_factory) -> None:
    org = await user_factory("Орг")
    eid = (await client.post("/events", headers=org["headers"],
                             json=_event_body(title="Разовое"))).json()["id"]
    await client.post(f"/events/{eid}/finish", headers=org["headers"])
    assert len(await _mine_titled(client, org["headers"], "Разовое")) == 1
