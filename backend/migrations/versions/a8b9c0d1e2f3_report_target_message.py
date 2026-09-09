"""Жалоба на конкретное сообщение чата (App Store 1.2).

Revision ID: a8b9c0d1e2f3
Revises: d6e7f8a9b0c1
Create Date: 2026-09-09
"""
import sqlalchemy as sa
from alembic import op

revision = "a8b9c0d1e2f3"
down_revision = "d6e7f8a9b0c1"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.add_column(
        "reports",
        sa.Column("target_message_id", sa.Uuid(), nullable=True),
    )
    op.create_foreign_key(
        "fk_reports_target_message",
        "reports",
        "messages",
        ["target_message_id"],
        ["id"],
        ondelete="SET NULL",
    )


def downgrade() -> None:
    op.drop_constraint("fk_reports_target_message", "reports", type_="foreignkey")
    op.drop_column("reports", "target_message_id")
