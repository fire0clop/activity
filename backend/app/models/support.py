import uuid

from sqlalchemy import String, Text
from sqlalchemy.orm import Mapped, mapped_column

from app.db.base import Base, TimestampMixin, UUIDPrimaryKey


class SupportTicket(Base, UUIDPrimaryKey, TimestampMixin):
    """Обращение из формы поддержки на сайте.

    Форма открыта без входа: у человека может не работать вход — именно с этим
    и пишут в поддержку чаще всего. Поэтому обратный адрес указывает он сам.
    """

    __tablename__ = "support_tickets"

    contact: Mapped[str] = mapped_column(String(200), nullable=False)
    message: Mapped[str] = mapped_column(Text, nullable=False)
    user_id: Mapped[uuid.UUID | None] = mapped_column(nullable=True)
    is_handled: Mapped[bool] = mapped_column(default=False, nullable=False)
