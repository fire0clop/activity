"""Импорт всех моделей, чтобы Base.metadata знал о таблицах (create_all / Alembic)."""

from app.models.conversation import Conversation, ConversationMember
from app.models.event import Event
from app.models.message import Message
from app.models.participation import Participation
from app.models.report import Block, DeviceToken, Report
from app.models.review import Review
from app.models.user import RefreshToken, User

__all__ = [
    "User",
    "RefreshToken",
    "Event",
    "Participation",
    "Conversation",
    "ConversationMember",
    "Message",
    "Review",
    "Report",
    "Block",
    "DeviceToken",
]
