"""add CHECK constraints: review rating range, event min/max and coords

Revision ID: e5f6a7b8c9d0
Revises: d4e5f6a7b8c9
Create Date: 2026-07-04
"""
from collections.abc import Sequence

from alembic import op

revision: str = "e5f6a7b8c9d0"
down_revision: str | None = "d4e5f6a7b8c9"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_check_constraint(
        "ck_reviews_rating_range", "reviews", "rating >= 1 AND rating <= 5"
    )
    op.create_check_constraint("ck_events_min_ge_1", "events", "min_participants >= 1")
    op.create_check_constraint(
        "ck_events_min_le_max",
        "events",
        "max_participants IS NULL OR min_participants <= max_participants",
    )
    op.create_check_constraint(
        "ck_events_coords_range",
        "events",
        "latitude >= -90 AND latitude <= 90 AND longitude >= -180 AND longitude <= 180",
    )


def downgrade() -> None:
    op.drop_constraint("ck_events_coords_range", "events", type_="check")
    op.drop_constraint("ck_events_min_le_max", "events", type_="check")
    op.drop_constraint("ck_events_min_ge_1", "events", type_="check")
    op.drop_constraint("ck_reviews_rating_range", "reviews", type_="check")
