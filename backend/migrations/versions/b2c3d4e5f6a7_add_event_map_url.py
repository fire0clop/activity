"""add events.map_url

Revision ID: b2c3d4e5f6a7
Revises: caa0ad615877
Create Date: 2026-06-14
"""
from typing import Sequence, Union

import sqlalchemy as sa
from alembic import op

revision: str = "b2c3d4e5f6a7"
down_revision: Union[str, None] = "caa0ad615877"
branch_labels: Union[str, Sequence[str], None] = None
depends_on: Union[str, Sequence[str], None] = None


def upgrade() -> None:
    op.add_column("events", sa.Column("map_url", sa.String(), nullable=True))


def downgrade() -> None:
    op.drop_column("events", "map_url")
