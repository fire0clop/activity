"""Импорт афиши из внешнего источника.

Руками завести тысячи мероприятий по стране невозможно, поэтому афиша наполняется
автоматически. Сейчас источник один — открытый API KudaGo: он не требует ключа и
отдаёт координаты, адрес, картинку и ссылку на первоисточник, то есть всё, без чего
карточка была бы непроверяемой.

Импорт идемпотентен: запись опознаётся по `source_ref`, повторный прогон обновляет
существующую карточку. Расписание у мероприятий сдвигается, и без этого афиша
быстро начала бы врать про даты.
"""

import logging
import re
from datetime import UTC, datetime, timedelta

import requests
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models.poster import PosterEvent

logger = logging.getLogger("poster_import")

API = "https://kudago.com/public-api/v1.4/events/"
SOURCE = "kudago"
REQUEST_TIMEOUT = 20

# Города, которые отдаёт источник. Это его потолок, а не наш выбор: покрытия
# «по всей России» у открытых источников нет, и обещать его нельзя.
CITIES = {
    "msk": "Москва",
    "spb": "Санкт-Петербург",
    "ekb": "Екатеринбург",
    "nnv": "Нижний Новгород",
    "kzn": "Казань",
}

# Категории источника → наши канонические ключи.
CATEGORY_MAP = {
    "concert": "concert",
    "theater": "theatre",
    "exhibition": "exhibition",
    "festival": "festival",
    "party": "party",
    "cinema": "cinema",
    "photo": "photo",
    "sport": "sport",
    "education": "study",
    "science": "study",
    "excursion": "walk",
    "ekskursii": "walk",
    "recreation": "walk",
    "quest": "quiz",
    "yarmarki": "festival",
    "fair": "festival",
    "stand-up": "party",
    "dance": "dance",
    "kids": "other",
    "entertainment": "other",
}

_FIELDS = ",".join([
    "id", "title", "short_title", "dates", "place", "price", "is_free",
    "categories", "images", "site_url", "description",
])


def _pick_category(slugs: list[str] | None) -> str | None:
    for slug in slugs or []:
        mapped = CATEGORY_MAP.get(slug)
        if mapped:
            return mapped
    return "other" if slugs else None


def _parse_price(text: str | None, is_free: bool) -> float | None:
    """Цена приходит фразой («от 500 рублей»). Берём первое число как ориентир «от»."""
    if is_free or not text:
        return None
    digits = re.sub(r"\s", "", text)
    match = re.search(r"\d+", digits)
    return float(match.group()) if match else None


def _next_start(dates: list[dict], now: datetime) -> datetime | None:
    """Ближайшая будущая дата.

    У бессрочных экспозиций `start` указывает на день открытия — иногда многолетней
    давности. Для них берём следующий слот из недельного расписания, иначе афиша
    показывала бы 2014 год.
    """
    upcoming = [d["start"] for d in dates
                if d.get("start") and d["start"] > now.timestamp() and not d.get("is_endless")]
    if upcoming:
        return datetime.fromtimestamp(min(upcoming), tz=UTC)

    for d in dates:
        if not (d.get("is_endless") or d.get("is_continuous")):
            continue
        if d.get("end") and d["end"] < now.timestamp():
            continue
        for sched in d.get("schedules") or []:
            days = sched.get("days_of_week") or []
            start_time = sched.get("start_time") or "12:00:00"
            hour, minute = (int(x) for x in start_time.split(":")[:2])
            for ahead in range(8):
                day = now + timedelta(days=ahead)
                if day.weekday() in days:
                    slot = day.replace(hour=hour, minute=minute, second=0, microsecond=0)
                    if slot > now:
                        return slot
    return None


MAX_PAGES = 6
PAGE_SIZE = 100


def fetch_city(city: str, *, limit: int) -> list[dict]:
    """Собрать записи по городу, перебирая страницы.

    Источник шумный: заметная часть выдачи — мероприятия, которые давно закончились
    (фильтр `actual_since` их не отсекает), и записи без места. Поэтому берём не одну
    страницу, а идём дальше, пока не наберём нужное или не кончатся страницы.

    `order_by=dates` намеренно не используем: с ним одно мероприятие возвращается
    отдельной записью на каждую дату показа, и страница из 40 записей содержит
    всего восемь разных событий.
    """
    collected: dict[int, dict] = {}
    for page in range(1, MAX_PAGES + 1):
        resp = requests.get(
            API,
            params={
                "location": city,
                "fields": _FIELDS,
                "expand": "place",
                "actual_since": int(datetime.now(UTC).timestamp()),
                "page": page,
                "page_size": PAGE_SIZE,
                "text_format": "text",
            },
            timeout=REQUEST_TIMEOUT,
        )
        resp.raise_for_status()
        payload = resp.json()
        for item in payload.get("results", []):
            collected.setdefault(item["id"], item)
        if len(collected) >= limit or not payload.get("next"):
            break
    return list(collected.values())


def to_poster_fields(raw: dict, now: datetime) -> dict | None:
    """Привести запись источника к нашей карточке. None — если брать нечего."""
    place = raw.get("place") or {}
    coords = place.get("coords") or {}
    lat, lon = coords.get("lat"), coords.get("lon")
    if lat is None or lon is None:
        return None  # без точки карточка бесполезна: афиша у нас геолокационная

    starts_at = _next_start(raw.get("dates") or [], now)
    if starts_at is None:
        return None

    title = (raw.get("short_title") or raw.get("title") or "").strip()
    if not title:
        return None

    images = raw.get("images") or []
    return {
        "source_ref": f"{SOURCE}:{raw['id']}",
        "title": title[:200].capitalize(),
        "description": (raw.get("description") or "").strip()[:2000] or None,
        "category": _pick_category(raw.get("categories")),
        "starts_at": starts_at,
        "venue": (place.get("title") or "")[:200] or None,
        "address": place.get("address"),
        "latitude": float(lat),
        "longitude": float(lon),
        "price_from": _parse_price(raw.get("price"), bool(raw.get("is_free"))),
        "is_free": bool(raw.get("is_free")),
        "image_url": images[0].get("image") if images else None,
        "source_url": raw.get("site_url"),
        "source_name": "KudaGo",
    }


async def import_city(db: AsyncSession, city: str, *, limit: int = 100) -> dict:
    """Импорт одного города. Возвращает счётчики для лога и ответа оператору."""
    import asyncio

    now = datetime.now(UTC)
    try:
        raw_items = await asyncio.to_thread(fetch_city, city, limit=limit)
    except Exception:  # noqa: BLE001 - недоступность источника не должна ронять вызов
        logger.exception("источник афиши недоступен: %s", city)
        return {"city": city, "fetched": 0, "created": 0, "updated": 0, "skipped": 0}

    created = updated = skipped = 0
    for raw in raw_items:
        fields = to_poster_fields(raw, now)
        if fields is None:
            skipped += 1
            continue
        existing = (
            await db.execute(
                select(PosterEvent).where(PosterEvent.source_ref == fields["source_ref"])
            )
        ).scalar_one_or_none()
        if existing is None:
            db.add(PosterEvent(
                **fields,
                location=func.ST_SetSRID(
                    func.ST_MakePoint(fields["longitude"], fields["latitude"]), 4326
                ),
                status="published",
            ))
            created += 1
        else:
            for key, value in fields.items():
                setattr(existing, key, value)
            existing.location = func.ST_SetSRID(
                func.ST_MakePoint(fields["longitude"], fields["latitude"]), 4326
            )
            updated += 1
    await db.commit()
    return {"city": city, "fetched": len(raw_items), "created": created,
            "updated": updated, "skipped": skipped}


async def import_all(db: AsyncSession, *, limit: int = 100) -> list[dict]:
    return [await import_city(db, city, limit=limit) for city in CITIES]
