"""subscription: follow a specific organizer (target_organizer_id)

Revision ID: b8c9d0e1f2a3
Revises: a7b8c9d0e1f2
Create Date: 2026-07-07
"""
from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "b8c9d0e1f2a3"
down_revision: str | None = "a7b8c9d0e1f2"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.add_column(
        "subscriptions",
        sa.Column(
            "target_organizer_id",
            sa.Uuid(),
            sa.ForeignKey("users.id", ondelete="CASCADE"),
            nullable=True,
        ),
    )
    op.create_index(
        "ix_subscriptions_target_organizer_id", "subscriptions", ["target_organizer_id"]
    )
    op.drop_constraint("ck_subscriptions_has_criterion", "subscriptions", type_="check")
    op.create_check_constraint(
        "ck_subscriptions_has_criterion",
        "subscriptions",
        "category IS NOT NULL "
        "OR (latitude IS NOT NULL AND longitude IS NOT NULL) "
        "OR target_organizer_id IS NOT NULL",
    )


def downgrade() -> None:
    op.drop_constraint("ck_subscriptions_has_criterion", "subscriptions", type_="check")
    op.create_check_constraint(
        "ck_subscriptions_has_criterion",
        "subscriptions",
        "category IS NOT NULL OR (latitude IS NOT NULL AND longitude IS NOT NULL)",
    )
    op.drop_index("ix_subscriptions_target_organizer_id", "subscriptions")
    op.drop_column("subscriptions", "target_organizer_id")
