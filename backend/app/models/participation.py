import uuid
from datetime import datetime

from sqlalchemy import DateTime, ForeignKey, String, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base, TimestampMixin, UUIDPrimaryKey


class Participation(Base, UUIDPrimaryKey, TimestampMixin):
    __tablename__ = "participations"
    __table_args__ = (UniqueConstraint("event_id", "user_id", name="uq_participation_event_user"),)

    event_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("events.id", ondelete="CASCADE"), index=True, nullable=False
    )
    user_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("users.id", ondelete="CASCADE"), index=True, nullable=False
    )
    # status: pending | accepted | rejected | waitlisted | cancelled
    status: Mapped[str] = mapped_column(String(16), default="pending", nullable=False)
    decided_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)
