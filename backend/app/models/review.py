import uuid

from sqlalchemy import Boolean, CheckConstraint, ForeignKey, Integer, String, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base, TimestampMixin, UUIDPrimaryKey


class Review(Base, UUIDPrimaryKey, TimestampMixin):
    __tablename__ = "reviews"
    __table_args__ = (
        UniqueConstraint("event_id", "author_id", "target_id", name="uq_review_triplet"),
        # Пришёл — обязана быть оценка 1–5; не пришёл — оценки нет вовсе (нечего оценивать).
        CheckConstraint(
            "(attended AND rating BETWEEN 1 AND 5) OR (NOT attended AND rating IS NULL)",
            name="ck_reviews_rating_range",
        ),
    )

    event_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("events.id", ondelete="CASCADE"), index=True, nullable=False
    )
    author_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), nullable=False
    )
    target_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), index=True, nullable=False
    )
    # Пусто, когда человек не пришёл: такой отзыв не участвует в среднем рейтинге.
    rating: Mapped[int | None] = mapped_column(Integer, nullable=True)
    comment: Mapped[str | None] = mapped_column(String, nullable=True)
    attended: Mapped[bool] = mapped_column(
        Boolean, default=True, server_default="true", nullable=False
    )
