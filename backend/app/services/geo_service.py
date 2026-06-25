"""Извлечение координат из ссылок Яндекс.Карт.

Поддерживает:
- текст с лишним (название + адрес + ссылка) — вытаскиваем саму ссылку;
- ссылки-точки с `pt` / `whatshere[point]` / `ll` (формат «lng,lat»);
- ссылки на организацию `/maps/org/...` — координат нет в URL, парсим страницу;
- короткие ссылки (yandex.ru/maps/-/…) — раскрываем через редирект;
- голую строку «55.75, 37.62».
"""

import logging
import re
from urllib.parse import parse_qs, urlparse

import requests

logger = logging.getLogger("geo")

_UA = (
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 "
    "(KHTML, like Gecko) Chrome/120 Safari/537.36"
)
_COORD_PAIR = re.compile(r"^\s*(-?\d{1,3}\.\d+)\s*,\s*(-?\d{1,3}\.\d+)\s*$")
_URL_RE = re.compile(r"https?://\S+")
_HTML_COORDS = re.compile(r'"coordinates":\s*\[\s*(-?\d+\.\d+),\s*(-?\d+\.\d+)\s*\]')


def _valid(lat: float, lng: float) -> bool:
    return -90 <= lat <= 90 and -180 <= lng <= 180


def _extract_url(text: str) -> str | None:
    m = _URL_RE.search(text)
    return m.group(0) if m else None


def _from_query(url: str) -> tuple[float, float] | None:
    qs = parse_qs(urlparse(url).query)
    for key in ("pt", "whatshere[point]", "ll"):
        if qs.get(key):
            parts = qs[key][0].split(",")
            if len(parts) >= 2:
                try:
                    lng, lat = float(parts[0]), float(parts[1])  # Яндекс: lng,lat
                    if _valid(lat, lng):
                        return lat, lng
                except ValueError:
                    continue
    return None


def _from_page(url: str) -> tuple[float, float] | None:
    """Для ссылок на организацию: координаты в состоянии страницы ("coordinates":[lng,lat])."""
    try:
        resp = requests.get(url, allow_redirects=True, timeout=12, headers={"User-Agent": _UA})
        # параметры могли появиться в финальном URL после редиректа
        if coords := _from_query(resp.url):
            return coords
        m = _HTML_COORDS.search(resp.text)
        if m:
            lng, lat = float(m.group(1)), float(m.group(2))
            if _valid(lat, lng):
                return lat, lng
    except Exception:  # noqa: BLE001
        logger.warning("geo: failed to fetch/parse page")
    return None


def parse_location(value: str) -> tuple[float, float] | None:
    """Возвращает (lat, lng) или None, если распознать не удалось."""
    value = value.strip()
    if not value:
        return None

    # Голые координаты "lat, lng".
    if m := _COORD_PAIR.match(value):
        lat, lng = float(m.group(1)), float(m.group(2))
        if _valid(lat, lng):
            return lat, lng

    url = _extract_url(value)
    if url is None or ("yandex" not in url and "ya.ru" not in url):
        return None

    # 1) координаты прямо в параметрах ссылки-точки
    if coords := _from_query(url):
        return coords
    # 2) ссылка на организацию / короткая — парсим страницу
    return _from_page(url)
