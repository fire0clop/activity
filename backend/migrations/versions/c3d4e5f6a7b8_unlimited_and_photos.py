"""max_participants nullable + photo galleries

Revision ID: c3d4e5f6a7b8
Revises: b2c3d4e5f6a7
Create Date: 2026-06-15
"""
from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "c3d4e5f6a7b8"
down_revision: str | None = "b2c3d4e5f6a7"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.alter_column("events", "max_participants", existing_type=sa.Integer(), nullable=True)
    op.add_column("events", sa.Column("photo_urls", sa.JSON(), server_default="[]", nullable=False))
    op.add_column("users", sa.Column("photo_urls", sa.JSON(), server_default="[]", nullable=False))


def downgrade() -> None:
    op.drop_column("users", "photo_urls")
    op.drop_column("events", "photo_urls")
    op.alter_column("events", "max_participants", existing_type=sa.Integer(), nullable=False)
