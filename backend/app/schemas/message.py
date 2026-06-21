import uuid
from datetime import datetime

from pydantic import BaseModel

from app.schemas.user import UserPublic


class MessageOut(BaseModel):
    id: uuid.UUID
    conversation_id: uuid.UUID
    sender: UserPublic | None
    text: str
    is_system: bool
    created_at: datetime


class MessagesOut(BaseModel):
    items: list[MessageOut]
    next_cursor: str | None
