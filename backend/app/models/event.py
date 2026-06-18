import uuid
from datetime import datetime

from geoalchemy2 import Geography
from sqlalchemy import JSON, Boolean, DateTime, Float, ForeignKey, Integer, Numeric, String
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base, TimestampMixin, UUIDPrimaryKey


class Event(Base, UUIDPrimaryKey, TimestampMixin):
    __tablename__ = "events"

    organizer_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), index=True, nullable=False
    )
    title: Mapped[str] = mapped_column(String(200), nullable=False)
    description: Mapped[str | None] = mapped_column(String, nullable=True)
    category: Mapped[str | None] = mapped_column(String(60), index=True, nullable=True)

    starts_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), index=True, nullable=False)
    ends_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)

    # Геоточка для запросов "рядом" + дубль lat/lng для удобного чтения без shapely.
    location: Mapped[object] = mapped_column(
        Geography(geometry_type="POINT", srid=4326), nullable=False
    )
    latitude: Mapped[float] = mapped_column(Float, nullable=False)
    longitude: Mapped[float] = mapped_column(Float, nullable=False)
    address: Mapped[str | None] = mapped_column(String, nullable=True)
    map_url: Mapped[str | None] = mapped_column(String, nullable=True)  # ссылка на точку Яндекс.Карт

    min_participants: Mapped[int] = mapped_column(Integer, default=2, nullable=False)
    # None = без ограничения по числу участников
    max_participants: Mapped[int | None] = mapped_column(Integer, nullable=True)
    photo_urls: Mapped[list] = mapped_column(JSON, default=list, server_default="[]", nullable=False)

    price: Mapped[float | None] = mapped_column(Numeric(10, 2), nullable=True)
    # price_split: free | per_person | shared
    price_split: Mapped[str] = mapped_column(String(16), default="free", nullable=False)

    cover_url: Mapped[str | None] = mapped_column(String, nullable=True)
    auto_accept: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)

    # status: open | full | closed | cancelled | finished
    status: Mapped[str] = mapped_column(String(16), default="open", index=True, nullable=False)
