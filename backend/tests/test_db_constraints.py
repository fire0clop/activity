"""CHECK-констрейнты на уровне БД — защита от невалидных данных в обход API."""

import uuid
from datetime import UTC, datetime, timedelta

import pytest
from sqlalchemy import text
from sqlalchemy.exc import IntegrityError

from app.db.session import SessionLocal
from app.models.user import User

pytestmark = pytest.mark.asyncio


async def _make_user(db) -> uuid.UUID:
    user = User(phone="+7999" + f"{uuid.uuid4().int % 10_000_000:07d}")
    db.add(user)
    await db.flush()
    return user.id


async def _insert_event(db, organizer: uuid.UUID, **overrides) -> None:
    params = {
        "id": uuid.uuid4(),
        "organizer_id": organizer,
        "title": "t",
        "starts_at": datetime.now(UTC) + timedelta(days=1),
        "lat": 55.75,
        "lng": 37.62,
        "min_p": 2,
        "max_p": 5,
    }
    params.update(overrides)
    await db.execute(
        text(
            "INSERT INTO events (id, organizer_id, title, starts_at, location, "
            "latitude, longitude, min_participants, max_participants, photo_urls, "
            "price_split, auto_accept, status, created_at, updated_at) "
            "VALUES (:id, :organizer_id, :title, :starts_at, "
            "ST_SetSRID(ST_MakePoint(:lng, :lat), 4326)::geography, "
            ":lat, :lng, :min_p, :max_p, '[]', 'free', false, 'open', now(), now())"
        ),
        params,
    )


async def test_review_rating_out_of_range_rejected(client):
    async with SessionLocal() as db:
        author = await _make_user(db)
        target = await _make_user(db)
        await _insert_event(db, author)
        await db.commit()

        event_id = (await db.execute(text("SELECT id FROM events LIMIT 1"))).scalar_one()
        for bad_rating in (0, 6):
            with pytest.raises(IntegrityError):
                await db.execute(
                    text("INSERT INTO reviews (id, event_id, author_id, target_id, rating, "
                         "created_at, updated_at) "
                         "VALUES (:id, :eid, :a, :t, :r, now(), now())"),
                    {"id": uuid.uuid4(), "eid": event_id, "a": author, "t": target,
                     "r": bad_rating},
                )
            await db.rollback()


async def test_event_min_greater_than_max_rejected(client):
    async with SessionLocal() as db:
        organizer = await _make_user(db)
        await db.commit()
        with pytest.raises(IntegrityError):
            await _insert_event(db, organizer, min_p=5, max_p=2)
        await db.rollback()


async def test_event_out_of_range_coords_rejected(client):
    async with SessionLocal() as db:
        organizer = await _make_user(db)
        await db.commit()
        with pytest.raises(IntegrityError):
            await _insert_event(db, organizer, lat=99.0)
        await db.rollback()
