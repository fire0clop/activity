import uuid

from sqlalchemy import CheckConstraint, Float, ForeignKey, String
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base, TimestampMixin, UUIDPrimaryKey


class Subscription(Base, UUIDPrimaryKey, TimestampMixin):
    """Подписка на новые события: по категории, по гео-области или по обоим сразу.

    Хотя бы один критерий обязателен (проверяется и в схеме, и констрейнтом).
    """

    __tablename__ = "subscriptions"
    __table_args__ = (
        CheckConstraint(
            "category IS NOT NULL OR (latitude IS NOT NULL AND longitude IS NOT NULL)",
            name="ck_subscriptions_has_criterion",
        ),
        CheckConstraint(
            "(latitude IS NULL) = (longitude IS NULL)",
            name="ck_subscriptions_coords_pair",
        ),
    )

    user_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), index=True, nullable=False
    )
    category: Mapped[str | None] = mapped_column(String(60), index=True, nullable=True)
    latitude: Mapped[float | None] = mapped_column(Float, nullable=True)
    longitude: Mapped[float | None] = mapped_column(Float, nullable=True)
    radius_km: Mapped[float] = mapped_column(Float, default=10, nullable=False)
