import pytest


@pytest.mark.asyncio
async def test_health(client) -> None:
    resp = await client.get("/health")
    assert resp.status_code == 200
    body = resp.json()
    assert body["status"] == "ok"
    assert body["checks"] == {"db": True, "redis": True}
