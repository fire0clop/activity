"""event reminders: reminder_24h_sent / reminder_2h_sent

Revision ID: c9d0e1f2a3b4
Revises: b8c9d0e1f2a3
Create Date: 2026-07-07
"""
from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "c9d0e1f2a3b4"
down_revision: str | None = "b8c9d0e1f2a3"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.add_column(
        "events",
        sa.Column("reminder_24h_sent", sa.Boolean(), server_default="false", nullable=False),
    )
    op.add_column(
        "events",
        sa.Column("reminder_2h_sent", sa.Boolean(), server_default="false", nullable=False),
    )


def downgrade() -> None:
    op.drop_column("events", "reminder_2h_sent")
    op.drop_column("events", "reminder_24h_sent")
