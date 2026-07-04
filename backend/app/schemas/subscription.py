import uuid

from pydantic import BaseModel, Field, model_validator


class SubscriptionCreateIn(BaseModel):
    category: str | None = Field(None, max_length=60)
    latitude: float | None = Field(None, ge=-90, le=90)
    longitude: float | None = Field(None, ge=-180, le=180)
    radius_km: float = Field(10, gt=0, le=200)

    @model_validator(mode="after")
    def _check_criterion(self) -> "SubscriptionCreateIn":
        if self.category is None and self.latitude is None:
            raise ValueError("Нужна категория и/или гео-точка")
        if (self.latitude is None) != (self.longitude is None):
            raise ValueError("latitude и longitude задаются вместе")
        return self


class SubscriptionOut(BaseModel):
    id: uuid.UUID
    category: str | None
    latitude: float | None
    longitude: float | None
    radius_km: float


class SubscriptionsOut(BaseModel):
    items: list[SubscriptionOut]
