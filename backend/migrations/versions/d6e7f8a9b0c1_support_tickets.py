"""Обращения из формы поддержки: таблица support_tickets

Revision ID: d6e7f8a9b0c1
Revises: c5d6e7f8a9b0
Create Date: 2026-08-27
"""
from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "d6e7f8a9b0c1"
down_revision: str | None = "c5d6e7f8a9b0"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "support_tickets",
        sa.Column("id", sa.Uuid(as_uuid=True), primary_key=True),
        sa.Column("contact", sa.String(200), nullable=False),
        sa.Column("message", sa.Text(), nullable=False),
        sa.Column("user_id", sa.Uuid(as_uuid=True), nullable=True),
        sa.Column("is_handled", sa.Boolean(), server_default=sa.false(), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True),
                  server_default=sa.func.now(), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True),
                  server_default=sa.func.now(), nullable=False),
    )
    # Разбор обращений идёт «сначала необработанные, свежие сверху».
    op.create_index("ix_support_tickets_handled_created", "support_tickets",
                    ["is_handled", "created_at"])


def downgrade() -> None:
    op.drop_index("ix_support_tickets_handled_created", table_name="support_tickets")
    op.drop_table("support_tickets")
