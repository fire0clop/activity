from datetime import datetime

from geoalchemy2 import Geography
from sqlalchemy import (
    Boolean,
    CheckConstraint,
    DateTime,
    Float,
    Numeric,
    String,
)
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base, TimestampMixin, UUIDPrimaryKey


class PosterEvent(Base, UUIDPrimaryKey, TimestampMixin):
    """Афиша — чужое мероприятие, на которое можно сходить.

    Принципиально отличается от Event: тут никто не собирает группу и не отбирает
    состав. Концерт состоится независимо от того, откликнулся кто-то или нет,
    у него нет организатора среди пользователей, нет чата и нет заявок.

    Связь с ядром продукта одна, но важная: из карточки афиши человек создаёт
    обычное событие «идём вместе», и оно ссылается сюда через Event.poster_id.
    Тогда на афише видно, сколько компаний уже собирается на этот концерт.
    """

    __tablename__ = "poster_events"
    __table_args__ = (
        CheckConstraint(
            "latitude >= -90 AND latitude <= 90 AND longitude >= -180 AND longitude <= 180",
            name="ck_poster_coords_range",
        ),
        CheckConstraint("status IN ('published', 'hidden')", name="ck_poster_status"),
    )

    title: Mapped[str] = mapped_column(String(200), nullable=False)
    description: Mapped[str | None] = mapped_column(String, nullable=True)
    category: Mapped[str | None] = mapped_column(String(60), index=True, nullable=True)

    starts_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), index=True, nullable=False
    )
    ends_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)

    venue: Mapped[str | None] = mapped_column(String(200), nullable=True)
    address: Mapped[str | None] = mapped_column(String, nullable=True)
    location: Mapped[object] = mapped_column(
        Geography(geometry_type="POINT", srid=4326), nullable=False
    )
    latitude: Mapped[float] = mapped_column(Float, nullable=False)
    longitude: Mapped[float] = mapped_column(Float, nullable=False)

    # Цена «от»: у афиши это ориентир, а не расчёт — билеты покупают не здесь.
    price_from: Mapped[float | None] = mapped_column(Numeric(10, 2), nullable=True)
    is_free: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)

    image_url: Mapped[str | None] = mapped_column(String, nullable=True)
    # Куда идти за билетом и кто источник — афиша обязана быть проверяемой.
    source_url: Mapped[str | None] = mapped_column(String, nullable=True)
    source_name: Mapped[str | None] = mapped_column(String(120), nullable=True)

    # Ключ записи у источника: "kudago:172178". По нему повторный импорт обновляет
    # карточку, а не плодит дубликаты — расписание у мероприятий сдвигается.
    source_ref: Mapped[str | None] = mapped_column(
        String(120), unique=True, index=True, nullable=True
    )

    status: Mapped[str] = mapped_column(
        String(16), default="published", server_default="published", index=True, nullable=False
    )
