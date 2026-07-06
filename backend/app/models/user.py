import uuid
from datetime import date, datetime

from sqlalchemy import JSON, Boolean, Date, DateTime, ForeignKey, Integer, Numeric, String
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base, TimestampMixin, UUIDPrimaryKey


class User(Base, UUIDPrimaryKey, TimestampMixin):
    __tablename__ = "users"

    phone: Mapped[str] = mapped_column(String(20), unique=True, index=True, nullable=False)
    password_hash: Mapped[str | None] = mapped_column(String, nullable=True)
    name: Mapped[str | None] = mapped_column(String(120), nullable=True)
    bio: Mapped[str | None] = mapped_column(String, nullable=True)
    avatar_url: Mapped[str | None] = mapped_column(String, nullable=True)
    photo_urls: Mapped[list] = mapped_column(JSON, default=list, server_default="[]", nullable=False)
    birth_date: Mapped[date | None] = mapped_column(Date, nullable=True)
    # gender: male | female | other | unspecified
    gender: Mapped[str] = mapped_column(String(16), default="unspecified", nullable=False)

    rating_avg: Mapped[float] = mapped_column(Numeric(3, 2), default=0, nullable=False)
    rating_count: Mapped[int] = mapped_column(Integer, default=0, nullable=False)
    events_created: Mapped[int] = mapped_column(Integer, default=0, nullable=False)
    events_attended: Mapped[int] = mapped_column(Integer, default=0, nullable=False)
    is_phone_verified: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)

    # Модерация: заблокированный оператором пользователь не проходит аутентификацию.
    is_banned: Mapped[bool] = mapped_column(
        Boolean, default=False, server_default="false", nullable=False
    )
    # Версия принятых правил/политики (App Store Guideline 1.2 для UGC).
    tos_accepted_version: Mapped[str | None] = mapped_column(String(20), nullable=True)

    @property
    def profile_completed(self) -> bool:
        """Профиль готов, когда заполнены имя, фото и «о себе» (ROADMAP §4)."""
        return bool(self.name and self.avatar_url and self.bio)

    @property
    def age(self) -> int | None:
        if not self.birth_date:
            return None
        today = date.today()
        return (
            today.year
            - self.birth_date.year
            - ((today.month, today.day) < (self.birth_date.month, self.birth_date.day))
        )


class RefreshToken(Base, UUIDPrimaryKey):
    __tablename__ = "refresh_tokens"

    user_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), index=True, nullable=False
    )
    token_hash: Mapped[str] = mapped_column(String(64), unique=True, index=True, nullable=False)
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), nullable=False)
    revoked: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False
    )
