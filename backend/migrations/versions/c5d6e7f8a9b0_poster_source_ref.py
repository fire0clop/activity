"""ключ источника для импорта афиши

Revision ID: c5d6e7f8a9b0
Revises: b4c5d6e7f8a9
Create Date: 2026-08-22
"""
from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "c5d6e7f8a9b0"
down_revision: str | None = "b4c5d6e7f8a9"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.add_column("poster_events", sa.Column("source_ref", sa.String(120), nullable=True))
    op.create_index(
        "ix_poster_events_source_ref", "poster_events", ["source_ref"], unique=True
    )


def downgrade() -> None:
    op.drop_index("ix_poster_events_source_ref", table_name="poster_events")
    op.drop_column("poster_events", "source_ref")
