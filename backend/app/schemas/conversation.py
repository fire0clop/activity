import uuid
from datetime import datetime

from pydantic import BaseModel, Field

from app.schemas.user import UserPublic


class LastMessage(BaseModel):
    text: str
    created_at: datetime
    sender_name: str | None


class ConversationListItem(BaseModel):
    id: uuid.UUID
    type: str
    title: str | None
    avatar_url: str | None
    event_id: uuid.UUID | None
    members_count: int
    last_message: LastMessage | None
    unread_count: int
    is_archived: bool


class ConversationDetail(ConversationListItem):
    members: list[UserPublic]
    my_role: str


class ConversationListOut(BaseModel):
    items: list[ConversationListItem]
    next_cursor: str | None


# --- V2 (этап 12) ---------------------------------------------------------

class CreateGroupIn(BaseModel):
    title: str = Field(..., max_length=200)
    member_ids: list[uuid.UUID] = Field(default_factory=list)
    from_event_id: uuid.UUID | None = None


class UpdateConversationIn(BaseModel):
    title: str | None = Field(default=None, max_length=200)


class AddMembersIn(BaseModel):
    user_ids: list[uuid.UUID]
