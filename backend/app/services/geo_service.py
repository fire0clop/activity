"""Извлечение координат из ссылок Яндекс.Карт.

Поддерживает:
- текст с лишним (название + адрес + ссылка) — вытаскиваем саму ссылку;
- ссылки-точки с `pt` / `whatshere[point]` / `ll` (формат «lng,lat»);
- ссылки на организацию `/maps/org/...` — координат нет в URL, парсим страницу;
- короткие ссылки (yandex.ru/maps/-/…) — раскрываем через редирект;
- голую строку «55.75, 37.62».
"""

import ipaddress
import logging
import re
import socket
from urllib.parse import parse_qs, urljoin, urlparse

import requests

logger = logging.getLogger("geo")

_UA = (
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 "
    "(KHTML, like Gecko) Chrome/120 Safari/537.36"
)
_COORD_PAIR = re.compile(r"^\s*(-?\d{1,3}\.\d+)\s*,\s*(-?\d{1,3}\.\d+)\s*$")
_URL_RE = re.compile(r"https?://\S+")
_HTML_COORDS = re.compile(r'"coordinates":\s*\[\s*(-?\d+\.\d+),\s*(-?\d+\.\d+)\s*\]')

# Anti-SSRF: разрешаем ходить только на эти хосты (и их поддомены), только http/https,
# только на публичные IP, и валидируем хост на КАЖДОМ редиректе.
_ALLOWED_HOSTS = ("yandex.ru", "ya.ru")
_MAX_REDIRECTS = 5
_MAX_BODY_BYTES = 2 * 1024 * 1024


def _valid(lat: float, lng: float) -> bool:
    return -90 <= lat <= 90 and -180 <= lng <= 180


def _host_allowed(host: str | None) -> bool:
    """Проверка ПО ХОСТУ, а не по подстроке: `yandex.attacker.com` не пройдёт."""
    if not host:
        return False
    host = host.lower()
    return any(host == h or host.endswith("." + h) for h in _ALLOWED_HOSTS)


def _resolves_to_public_ip(host: str) -> bool:
    """Резолвит хост и требует, чтобы ВСЕ адреса были публичными.

    Отсекает SSRF к loopback/приватным/link-local диапазонам (metadata облака 169.254.169.254,
    внутренние контейнеры docker-сети, localhost).
    """
    try:
        infos = socket.getaddrinfo(host, None)
    except socket.gaierror:
        return False
    for info in infos:
        ip = ipaddress.ip_address(info[4][0])
        if (ip.is_private or ip.is_loopback or ip.is_link_local
                or ip.is_reserved or ip.is_multicast or ip.is_unspecified):
            return False
    return True


def _url_is_safe(url: str) -> bool:
    parsed = urlparse(url)
    if parsed.scheme not in ("http", "https"):
        return False
    if not _host_allowed(parsed.hostname):
        return False
    return _resolves_to_public_ip(parsed.hostname)


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


def _safe_get(url: str) -> requests.Response | None:
    """GET с ручной обработкой редиректов: валидируем хост/IP на каждом шаге (anti-SSRF)."""
    current = url
    for _ in range(_MAX_REDIRECTS):
        if not _url_is_safe(current):
            logger.warning("geo: blocked non-allowed/private URL")
            return None
        resp = requests.get(
            current,
            allow_redirects=False,
            timeout=12,
            headers={"User-Agent": _UA},
            stream=True,
        )
        if resp.is_redirect or resp.is_permanent_redirect:
            location = resp.headers.get("Location")
            resp.close()
            if not location:
                return None
            current = urljoin(current, location)
            continue
        return resp
    return None


def _from_page(url: str) -> tuple[float, float] | None:
    """Для ссылок на организацию: координаты в состоянии страницы ("coordinates":[lng,lat])."""
    try:
        resp = _safe_get(url)
        if resp is None:
            return None
        try:
            raw = resp.raw.read(_MAX_BODY_BYTES + 1, decode_content=True)
            # параметры могли появиться в финальном URL после редиректа
            if coords := _from_query(resp.url):
                return coords
            if len(raw) > _MAX_BODY_BYTES:
                return None
            page = raw.decode(resp.encoding or "utf-8", errors="replace")
        finally:
            resp.close()
        m = _HTML_COORDS.search(page)
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
    if url is None or not _host_allowed(urlparse(url).hostname):
        return None

    # 1) координаты прямо в параметрах ссылки-точки
    if coords := _from_query(url):
        return coords
    # 2) ссылка на организацию / короткая — парсим страницу
    return _from_page(url)
