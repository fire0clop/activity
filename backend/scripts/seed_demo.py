"""Витринные данные для проверки ревьюером App Store.

Первая заявка получила отказ по 2.1(a) «demo account must include pre-populated
content» по двум причинам сразу:

1. События заводились на ближайшие сутки-двое, а проверка идёт через несколько
   дней — к моменту ревью все они уже прошли, и лента была пуста.
2. События были только в Москве, а устройство проверяющего — в Купертино.
   Лента показывает то, что рядом, поэтому даже свежие события он бы не увидел.

Поэтому здесь: даты на 3–40 дней вперёд и одинаковый набор в двух точках.
Скрипт идемпотентный — перед каждой повторной заявкой достаточно запустить его
снова, чтобы обновить даты.

    docker exec -w /app -e PYTHONPATH=/app backend-api-1 python scripts/seed_demo.py
"""

import asyncio
import io
import pathlib
import uuid
from datetime import UTC, datetime, timedelta

from fastapi import UploadFile
from sqlalchemy import delete, select
from starlette.datastructures import Headers

from app.db.session import SessionLocal
from app.models.conversation import Conversation, ConversationMember
from app.models.event import Event
from app.models.message import Message
from app.models.participation import Participation
from app.models.request import CompanyRequest, RequestSupport
from app.models.review import Review
from app.models.user import User
from app.services.storage_service import get_storage

ASSETS = pathlib.Path(__file__).parent / "demo_assets"
REVIEWER_NAME = "Apple Review"

ORGANIZERS = [
    ("+79995551001", "Аня Ковалёва",
     "Бегаю по утрам, вожу на Патриаршие за лучшим кофе. Люблю компанию, но без обязательств.", 4.9, 23),
    ("+79995551002", "Марк Гринёв",
     "Собираю людей на теннис и настолки. Обещаю — никакой неловкости.", 4.8, 17),
    ("+79995551003", "Лена Соболь",
     "Фотографирую город на плёнку. Зову гулять там, где красиво.", 5.0, 11),
    ("+79995551004", "Тимур Асланов",
     "Играю в футбол по средам, хожу на концерты по пятницам.", 4.7, 31),
]

# (обложка, название, описание, категория, дней вперёд, час, сдвиг широты,
#  сдвиг долготы, адрес, максимум, цена, оплата)
PLAN = [
    ("board", "Настолки до последнего автобуса", "Ave Caesar, Codenames и что принесёте. Правила объясню.",
     "boardgames", 3, 19, 0.009, 0.000, 6, 500, "per_person"),
    ("run", "Утренний бег по набережной", "Лёгкие 5 км вдоль воды, темп разговорный. После — кофе у моста.",
     "walk", 4, 8, -0.006, -0.013, 8, None, "free"),
    ("coffee", "Кофе и разговоры без телефонов", "Час на новую обжарку и живой разговор. Незнакомым особенно рады.",
     "coffee", 5, 12, 0.014, -0.025, 5, None, "free"),
    ("tennis", "Теннис в парке", "Есть корт на два часа, нужен четвёртый. Уровень любой, лишь бы через сетку.",
     "sport", 7, 18, -0.035, -0.064, 4, 1200, "shared"),
    ("volley", "Волейбол на площадке", "Играем два часа, состав собирается на месте. Мяч мой.",
     "sport", 9, 17, -0.041, -0.065, 12, None, "free"),
    ("photo", "Фотопрогулка по старым кварталам", "Снимаем плёнку и цифру, маршрут по дворам. Возьмите то, чем снимаете.",
     "photo", 12, 15, -0.013, 0.008, 10, None, "free"),
    ("bike", "Велозаезд вдоль реки", "25 км в спокойном темпе, с остановками. Прокат рядом, если своего нет.",
     "bike", 16, 11, -0.022, -0.013, 8, None, "free"),
    ("concert", "Идём на концерт вместе", "Беру два билета, ищу компанию. Встречаемся у входа за полчаса.",
     "concert", 21, 20, 0.020, -0.029, 4, 2500, "per_person"),
    ("quiz", "Квиз в баре по четвергам", "Нужен человек, который шарит в кино. Остальное закрываем сами.",
     "quiz", 28, 20, 0.001, 0.017, 6, 800, "per_person"),
]

CITIES = [
    # (ключ, широта, долгота, названия мест по порядку из PLAN)
    ("msk", 55.7510, 37.6180, [
        "Антикафе «Кубик», Мясницкая", "Пушкинская набережная", "Патриаршие пруды",
        "Корты в Лужниках", "Площадки на Воробьёвых горах", "Метро «Третьяковская»",
        "Крымская набережная", "Главclub, Орджоникидзе", "Бар «Ровесник»"]),
    # Устройство проверяющего физически в Купертино: без набора рядом с ним
    # лента снова окажется пустой.
    ("cup", 37.3349, -122.0090, [
        "Board game cafe, Stevens Creek Blvd", "Rancho San Antonio trailhead",
        "Coffee bar on Main Street", "Memorial Park tennis courts",
        "Sand volleyball court, Memorial Park", "Downtown Sunnyvale",
        "Stevens Creek Trail", "City Hall plaza stage", "Pub on Murphy Avenue"]),
]

WISHES = [
    ("tennis", "Ищу партнёра на теннис по будням вечером. Ракетка есть, уровень средний.", "week"),
    ("bar", "Хочу в бар без повода и без плана. Просто поговорить с живыми людьми.", "week"),
    ("museum", "Кто-нибудь идёт на новую выставку? Одному ходить скучно.", "week"),
    ("food", "Хочу попробовать местную кухню в компании, а не в одиночку.", "week"),
]

CHAT = [
    (0, "Всем привет! Стол забронировал на 19:00, второй этаж у окна."),
    (1, "Отлично. Я захвачу Codenames и Ave Caesar."),
    (3, "А правила объясните? Я в настолках новичок."),
    (0, "Конечно, начнём с простого. Никто не останется в стороне."),
    (2, "Буду минут на десять позже, метро подводит."),
    (0, "Не страшно, всё равно раскладываемся минут двадцать."),
]

REVIEWS = [
    (1, 5, "Собрал всех вовремя, объяснил правила новичкам. Приду ещё."),
    (3, 5, "Спокойно и без неловкости. Редкий случай, когда компания сложилась сама."),
    (2, 4, "Хорошо организовано, только место шумноватое."),
]


async def _upload(storage, path: pathlib.Path, subdir: str) -> str:
    up = UploadFile(file=io.BytesIO(path.read_bytes()), filename=path.name,
                    headers=Headers({"content-type": "image/jpeg"}))
    return await storage.save(up, subdir=subdir)


async def main() -> None:
    storage = get_storage()
    now = datetime.now(UTC)

    async with SessionLocal() as db:
        # 1. Организаторы
        people: list[User] = []
        for phone, name, bio, rating, count in ORGANIZERS:
            u = (await db.execute(select(User).where(User.phone == phone))).scalar_one_or_none()
            if u is None:
                u = User(id=uuid.uuid4(), phone=phone, is_phone_verified=True)
                db.add(u)
            u.name, u.bio = name, bio
            u.rating_avg, u.rating_count = rating, count
            u.events_created, u.events_attended = count // 3, count
            u.birth_date = now.date() - timedelta(days=365 * 28)
            u.gender = "unspecified"
            u.tos_accepted_version = "1.0"
            if not u.avatar_url:
                u.avatar_url = await _upload(storage, ASSETS / f"avatar_{len(people)}.jpg", "avatars")
            await db.flush()
            people.append(u)
        print(f"организаторов: {len(people)}")

        reviewer = (await db.execute(
            select(User).where(User.name == REVIEWER_NAME))).scalar_one_or_none()

        # 2. Старые витринные события убираем — иначе даты копятся и снова протухают
        old = (await db.execute(select(Event).where(
            Event.organizer_id.in_([p.id for p in people])))).scalars().all()
        for e in old:
            await db.delete(e)
        await db.flush()
        if old:
            print(f"убрано прошлых витринных событий: {len(old)}")

        # 3. Свежие события в каждом городе
        covers: dict[str, str] = {}
        created: dict[str, list[Event]] = {}
        for ci, (key, lat0, lng0, places) in enumerate(CITIES):
            created[key] = []
            for i, (cov, title, desc, cat, days, hour, dlat, dlng, mx, price, split) in enumerate(PLAN):
                if cov not in covers:
                    covers[cov] = await _upload(storage, ASSETS / f"cover_{cov}.jpg", "covers")
                org = people[(i + ci) % len(people)]
                starts = (now + timedelta(days=days)).replace(
                    hour=hour, minute=0, second=0, microsecond=0)
                ev = Event(
                    id=uuid.uuid4(), organizer_id=org.id, title=title, description=desc,
                    category=cat, starts_at=starts, ends_at=starts + timedelta(hours=2),
                    latitude=lat0 + dlat, longitude=lng0 + dlng,
                    address=places[i], min_participants=2, max_participants=mx,
                    price=price, price_split=split, auto_accept=True,
                    cover_url=covers[cov], status="open",
                )
                ev.location = f"SRID=4326;POINT({lng0 + dlng} {lat0 + dlat})"
                db.add(ev)
                await db.flush()
                db.add(Participation(event_id=ev.id, user_id=org.id, status="accepted",
                                     decided_at=now))
                # Живые счётчики: часть организаторов ходит друг к другу.
                for j, p in enumerate(people):
                    if p.id != org.id and (i + j) % 3 == 0:
                        db.add(Participation(event_id=ev.id, user_id=p.id,
                                             status="accepted", decided_at=now))
                created[key].append(ev)
            print(f"событий в «{key}»: {len(created[key])}")

        # 4. Желания «Хочу» в обоих городах
        await db.execute(delete(RequestSupport))
        await db.execute(delete(CompanyRequest))
        await db.flush()
        for ci, (key, lat0, lng0, _places) in enumerate(CITIES):
            for i, (cat, text, window) in enumerate(WISHES):
                author = people[(i + ci) % len(people)]
                rq = CompanyRequest(
                    id=uuid.uuid4(), author_id=author.id, category=cat, text=text,
                    latitude=lat0 + 0.004 * i, longitude=lng0 - 0.005 * i,
                    area=None, radius_km=10, when_window=window, status="open",
                    expires_at=now + timedelta(days=30),
                )
                rq.location = f"SRID=4326;POINT({lng0 - 0.005 * i} {lat0 + 0.004 * i})"
                db.add(rq)
                await db.flush()
                for j, p in enumerate(people):
                    if p.id != author.id and (i + j) % 2 == 0:
                        db.add(RequestSupport(request_id=rq.id, user_id=p.id))
        print(f"желаний: {len(WISHES) * len(CITIES)}")

        # 5. Чат в первом событии каждого города плюс аккаунт ревьюера в составе
        for key in created:
            ev = created[key][0]
            # Название обязательно: в списке чатов беседа без него — пустая строка.
            conv = Conversation(id=uuid.uuid4(), type="event", title=ev.title,
                                event_id=ev.id, created_by=ev.organizer_id)
            db.add(conv)
            await db.flush()
            members = list(people)
            if reviewer is not None:
                members.append(reviewer)
                db.add(Participation(event_id=ev.id, user_id=reviewer.id,
                                     status="accepted", decided_at=now))
            for p in members:
                db.add(ConversationMember(
                    conversation_id=conv.id, user_id=p.id,
                    role="owner" if p.id == ev.organizer_id else "member"))
            base = now - timedelta(minutes=48)
            for k, (who, text) in enumerate(CHAT):
                sender = people[who] if who < len(people) else reviewer
                if sender is None:
                    continue
                m = Message(conversation_id=conv.id, sender_id=sender.id, text=text)
                m.created_at = base + timedelta(minutes=k * 7)
                db.add(m)
        print(f"чатов с перепиской: {len(created)}")

        # 6. Отзывы организатору первого события — чтобы профиль не был пустым
        target = created[CITIES[0][0]][0]
        await db.execute(delete(Review))
        await db.flush()
        for author_i, rating, comment in REVIEWS:
            if people[author_i].id == target.organizer_id:
                continue
            db.add(Review(event_id=target.id, author_id=people[author_i].id,
                          target_id=target.organizer_id, rating=rating,
                          comment=comment, attended=True))
        print(f"отзывов: {len(REVIEWS)}")

        await db.commit()

    print("\nГотово. Ближайшее событие через 3 дня, самое дальнее через 28.")


if __name__ == "__main__":
    asyncio.run(main())
