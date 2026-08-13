import uuid
from datetime import datetime

from geoalchemy2 import Geography
from sqlalchemy import (
    CheckConstraint,
    DateTime,
    Float,
    ForeignKey,
    String,
    UniqueConstraint,
)
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base, TimestampMixin, UUIDPrimaryKey


class CompanyRequest(Base, UUIDPrimaryKey, TimestampMixin):
    """«Ищу компанию» — намерение без обязательств.

    Обратная сторона события: не «я организую теннис в 19:00 на корте №3», а «хочу
    на теннис где-то на неделе, район такой-то». Заявить желание готовы десятки,
    а взять на себя организацию — единицы; раньше продукт требовал второго от всех,
    и в пустом городе лента оставалась пустой.

    Точного времени и адреса здесь нет намеренно: они появляются только когда
    кто-то берёт запрос на себя и заводит из него настоящее событие.
    """

    __tablename__ = "company_requests"
    __table_args__ = (
        CheckConstraint(
            "latitude >= -90 AND latitude <= 90 AND longitude >= -180 AND longitude <= 180",
            name="ck_requests_coords_range",
        ),
        CheckConstraint(
            "when_window IN ('today', 'tomorrow', 'weekend', 'week')",
            name="ck_requests_when_window",
        ),
        CheckConstraint("radius_km > 0 AND radius_km <= 100", name="ck_requests_radius"),
    )

    author_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), index=True, nullable=False
    )
    # Категория обязательна: она и есть суть запроса («чем хочется заняться»).
    category: Mapped[str] = mapped_column(String(60), index=True, nullable=False)
    text: Mapped[str | None] = mapped_column(String(500), nullable=True)

    location: Mapped[object] = mapped_column(
        Geography(geometry_type="POINT", srid=4326), nullable=False
    )
    latitude: Mapped[float] = mapped_column(Float, nullable=False)
    longitude: Mapped[float] = mapped_column(Float, nullable=False)
    area: Mapped[str | None] = mapped_column(String(200), nullable=True)
    radius_km: Mapped[float] = mapped_column(Float, default=10, nullable=False)

    # Окно вместо точного времени: today | tomorrow | weekend | week
    when_window: Mapped[str] = mapped_column(String(16), nullable=False)

    # open | fulfilled | cancelled | expired
    status: Mapped[str] = mapped_column(String(16), default="open", index=True, nullable=False)
    fulfilled_event_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("events.id", ondelete="SET NULL"), nullable=True
    )
    # Желание протухает вместе со своим окном — мёртвые «хочу» ленту не засоряют.
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), index=True, nullable=False)


class RequestSupport(Base, UUIDPrimaryKey, TimestampMixin):
    """«+1» к чужому запросу.

    Самый дешёвый сигнал спроса: организатору видно, что теннис хотят пятеро,
    а не один человек. Это то, ради чего запросы вообще существуют.
    """

    __tablename__ = "request_supports"
    __table_args__ = (
        UniqueConstraint("request_id", "user_id", name="uq_request_support"),
    )

    request_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("company_requests.id", ondelete="CASCADE"), index=True, nullable=False
    )
    user_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), index=True, nullable=False
    )
