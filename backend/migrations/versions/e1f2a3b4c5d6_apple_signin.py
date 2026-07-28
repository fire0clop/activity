"""apple sign-in: apple_user_id, phone nullable, identity constraint

Revision ID: e1f2a3b4c5d6
Revises: d0e1f2a3b4c5
Create Date: 2026-07-08
"""
from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "e1f2a3b4c5d6"
down_revision: str | None = "d0e1f2a3b4c5"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.add_column("users", sa.Column("apple_user_id", sa.String(length=255), nullable=True))
    op.create_unique_constraint("uq_users_apple_user_id", "users", ["apple_user_id"])
    op.create_index("ix_users_apple_user_id", "users", ["apple_user_id"])
    op.alter_column("users", "phone", existing_type=sa.String(length=20), nullable=True)
    op.create_check_constraint(
        "ck_users_has_identity",
        "users",
        "phone IS NOT NULL OR apple_user_id IS NOT NULL",
    )


def downgrade() -> None:
    op.drop_constraint("ck_users_has_identity", "users", type_="check")
    op.alter_column("users", "phone", existing_type=sa.String(length=20), nullable=False)
    op.drop_index("ix_users_apple_user_id", "users")
    op.drop_constraint("uq_users_apple_user_id", "users", type_="unique")
    op.drop_column("users", "apple_user_id")
