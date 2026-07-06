"""Тесты security-фиксов из Блока 0 аудита: anti-SSRF в geo, валидация телефона,
владение фото при удалении."""

import pytest

from app.services.geo_service import _host_allowed, _url_is_safe, parse_location

# --- SSRF: проверка хоста, а не подстроки ---------------------------------

def test_host_allowed_accepts_yandex_and_subdomains() -> None:
    assert _host_allowed("yandex.ru")
    assert _host_allowed("maps.yandex.ru")
    assert _host_allowed("ya.ru")


def test_host_allowed_rejects_lookalikes_and_internal() -> None:
    # поддомен-ловушка и подстрока в пути раньше проходили substring-проверку
    assert not _host_allowed("yandex.attacker.com")
    assert not _host_allowed("attacker.com")
    assert not _host_allowed("169.254.169.254")
    assert not _host_allowed(None)


def test_url_is_safe_rejects_bad_scheme_and_host() -> None:
    assert not _url_is_safe("ftp://yandex.ru/x")
    assert not _url_is_safe("http://yandex.attacker.com/steal")
    # metadata-эндпоинт облака с ya.ru в query — хост не yandex, отклоняем без сетевого вызова
    assert not _url_is_safe("http://169.254.169.254/latest/meta-data/?q=ya.ru")


def test_parse_location_ignores_non_yandex_url_without_network() -> None:
    # host-проверка отсекает до любого requests.get — SSRF невозможен
    assert parse_location("смотри тут http://yandex.attacker.com/maps/org/1") is None
    assert parse_location("http://169.254.169.254/x/ya.ru") is None


def test_parse_location_still_reads_plain_coords() -> None:
    assert parse_location("55.75, 37.62") == (55.75, 37.62)


# --- Валидация формата телефона -------------------------------------------

@pytest.mark.asyncio
async def test_request_code_rejects_invalid_phone(client) -> None:
    for bad in ["notaphone", "+7999abc0000", "89990001100", "+7999000110000"]:
        resp = await client.post("/auth/request-code", json={"phone": bad})
        assert resp.status_code == 422, bad


@pytest.mark.asyncio
async def test_request_code_accepts_valid_phone(client) -> None:
    resp = await client.post("/auth/request-code", json={"phone": "+79990001234"})
    assert resp.status_code == 200


# --- delete_photo: удаление только своего фото ----------------------------

@pytest.mark.asyncio
async def test_delete_photo_of_unknown_url_is_404(client, user_factory) -> None:
    u = await user_factory("Орг")
    # url, которого нет в списке пользователя, не должен трогать хранилище и даёт 404
    resp = await client.delete(
        "/users/me/photos",
        headers=u["headers"],
        params={"url": "http://localhost:8000/media/user_photos/someoneelse.jpg"},
    )
    assert resp.status_code == 404
