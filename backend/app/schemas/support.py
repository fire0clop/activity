from pydantic import BaseModel, Field


class SupportTicketIn(BaseModel):
    contact: str = Field(..., min_length=3, max_length=200)
    message: str = Field(..., min_length=10, max_length=4000)
