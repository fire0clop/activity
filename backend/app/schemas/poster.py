import uuid
from datetime import datetime

from pydantic import BaseModel, Field, field_validator

from app.core.categories import normalize


class PosterCreateIn(BaseModel):
    """Заводит карточку афиши. Доступно только оператору — это не пользовательский контент."""

    title: str = Field(..., min_length=2, max_length=200)
    description: str | None = None
    category: str | None = Field(default=None, max_length=60)
    starts_at: datetime
    ends_at: datetime | None = None
    venue: str | None = Field(default=None, max_length=200)
    address: str | None = None
    latitude: float = Field(..., ge=-90, le=90)
    longitude: float = Field(..., ge=-180, le=180)
    price_from: float | None = Field(default=None, ge=0)
    is_free: bool = False
    image_url: str | None = None
    source_url: str | None = None
    source_name: str | None = Field(default=None, max_length=120)

    @field_validator("category")
    @classmethod
    def _norm(cls, v: str | None) -> str | None:
        return normalize(v)


class PosterUpdateIn(BaseModel):
    title: str | None = Field(default=None, min_length=2, max_length=200)
    description: str | None = None
    category: str | None = Field(default=None, max_length=60)
    starts_at: datetime | None = None
    ends_at: datetime | None = None
    venue: str | None = Field(default=None, max_length=200)
    address: str | None = None
    price_from: float | None = Field(default=None, ge=0)
    is_free: bool | None = None
    image_url: str | None = None
    source_url: str | None = None
    source_name: str | None = Field(default=None, max_length=120)
    status: str | None = Field(default=None, pattern="^(published|hidden)$")

    @field_validator("category")
    @classmethod
    def _norm(cls, v: str | None) -> str | None:
        return normalize(v)


class PosterItem(BaseModel):
    id: uuid.UUID
    title: str
    description: str | None
    category: str | None
    starts_at: datetime
    ends_at: datetime | None
    venue: str | None
    address: str | None
    latitude: float
    longitude: float
    distance_km: float | None
    price_from: float | None
    is_free: bool
    image_url: str | None
    source_url: str | None
    source_name: str | None
    # Сколько компаний уже собирается на это мероприятие — главный мост к ядру продукта.
    gatherings_count: int
    status: str


class PosterOut(BaseModel):
    items: list[PosterItem]
    next_cursor: str | None


class CategoryItem(BaseModel):
    key: str
    title: str
    is_canonical: bool
    usage: int


class CategoriesOut(BaseModel):
    items: list[CategoryItem]
