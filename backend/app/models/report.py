import uuid

from sqlalchemy import ForeignKey, String, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base, TimestampMixin, UUIDPrimaryKey


class Report(Base, UUIDPrimaryKey, TimestampMixin):
    __tablename__ = "reports"

    reporter_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), nullable=False
    )
    target_user_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), nullable=True
    )
    target_event_id: Mapped[uuid.UUID | None] = mapped_column(
        ForeignKey("events.id", ondelete="CASCADE"), nullable=True
    )
    # reason: spam | inappropriate | safety | other
    reason: Mapped[str] = mapped_column(String(32), nullable=False)
    comment: Mapped[str | None] = mapped_column(String, nullable=True)
    # status: new | reviewed | actioned
    status: Mapped[str] = mapped_column(String(16), default="new", nullable=False)


class Block(Base, UUIDPrimaryKey, TimestampMixin):
    __tablename__ = "blocks"
    __table_args__ = (UniqueConstraint("blocker_id", "blocked_id", name="uq_block_pair"),)

    blocker_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), index=True, nullable=False
    )
    blocked_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), index=True, nullable=False
    )


class DeviceToken(Base, UUIDPrimaryKey, TimestampMixin):
    __tablename__ = "device_tokens"

    user_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), index=True, nullable=False
    )
    token: Mapped[str] = mapped_column(String, unique=True, index=True, nullable=False)
    # platform: ios | android
    platform: Mapped[str] = mapped_column(String(16), nullable=False)
