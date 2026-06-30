"""Пересоздание тестовых событий в новом формате: `python -m app.seed`.

Удаляет старые события и создаёт новые — с map_url (ссылка Яндекс.Карт) и,
для части, без ограничения по числу участников (max_participants=None).
"""

import asyncio
from datetime import UTC, datetime, timedelta

from sqlalchemy import delete, func, select

from app.db.session import SessionLocal
from app.models.event import Event
from app.models.participation import Participation
from app.models.user import User

# (title, category, lat, lng, address, map_url, max_participants, price)
SEED_EVENTS = [
    ("Гидроциклы на Клязьме", "watersport", 55.91, 37.81, "Пирс №3, прокат «Волна»",
     "https://yandex.ru/maps/?pt=37.81,55.91&z=15", 5, 4000),
    ("Теннис в выходной", "tennis", 55.75, 37.62, "Корты в Лужниках",
     "https://yandex.ru/maps/?pt=37.62,55.75&z=15", 4, 1200),
    ("Сходить на концерт", "music", 55.77, 37.59, "Главclub",
     "https://yandex.ru/maps/?pt=37.59,55.77&z=15", None, 2500),   # без ограничения
    ("Настолки вечером", "boardgames", 55.74, 37.60, "Антикафе «Кубик»",
     "https://yandex.ru/maps/?pt=37.60,55.74&z=15", 6, 500),
    ("Прогулка по парку", "walk", 55.72, 37.55, "Парк Горького, главный вход",
     "https://yandex.ru/maps/?pt=37.55,55.72&z=15", None, None),   # без ограничения, бесплатно
]


async def main() -> None:
    async with SessionLocal() as db:
        # Удаляем старые события (participations/conversations уйдут по FK cascade).
        await db.execute(delete(Event))
        await db.commit()

        organizer = (
            await db.execute(select(User).where(User.phone == "+79990000000"))
        ).scalar_one_or_none()
        if organizer is None:
            organizer = User(
                phone="+79990000000",
                name="Демо Организатор",
                bio="Создаю движухи по выходным",
                avatar_url=None,
                is_phone_verified=True,
            )
            db.add(organizer)
            await db.flush()
        organizer.events_created = 0

        now = datetime.now(UTC)
        for i, (title, cat, lat, lng, addr, map_url, maxp, price) in enumerate(SEED_EVENTS):
            event = Event(
                organizer_id=organizer.id,
                title=title,
                description="Тестовое событие для разработки фронта.",
                category=cat,
                starts_at=now + timedelta(days=i, hours=3),
                ends_at=now + timedelta(days=i, hours=6),
                location=func.ST_SetSRID(func.ST_MakePoint(lng, lat), 4326),
                latitude=lat,
                longitude=lng,
                address=addr,
                map_url=map_url,
                min_participants=2,
                max_participants=maxp,
                price=price,
                price_split="shared" if price else "free",
                status="open",
            )
            db.add(event)
            await db.flush()
            db.add(Participation(event_id=event.id, user_id=organizer.id, status="accepted",
                                 decided_at=now))
            organizer.events_created += 1

        await db.commit()
        unlimited = sum(1 for e in SEED_EVENTS if e[6] is None)
        print(f"Создано {len(SEED_EVENTS)} событий ({unlimited} без ограничения по людям).")


if __name__ == "__main__":
    asyncio.run(main())
