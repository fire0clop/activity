"""неявка: users.no_show_count, reviews.attended, оценка становится необязательной

Revision ID: f2a3b4c5d6e7
Revises: e1f2a3b4c5d6
Create Date: 2026-08-15
"""
from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "f2a3b4c5d6e7"
down_revision: str | None = "e1f2a3b4c5d6"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.add_column(
        "users",
        sa.Column("no_show_count", sa.Integer(), server_default="0", nullable=False),
    )
    op.add_column(
        "reviews",
        sa.Column("attended", sa.Boolean(), server_default="true", nullable=False),
    )
    # Отзыв «не пришёл» оценки не несёт — снимаем NOT NULL с rating.
    op.alter_column("reviews", "rating", existing_type=sa.Integer(), nullable=True)
    # Старое ограничение требовало оценку всегда; новое связывает её с фактом явки.
    op.drop_constraint("ck_reviews_rating_range", "reviews", type_="check")
    op.create_check_constraint(
        "ck_reviews_rating_range",
        "reviews",
        "(attended AND rating BETWEEN 1 AND 5) OR (NOT attended AND rating IS NULL)",
    )


def downgrade() -> None:
    op.drop_constraint("ck_reviews_rating_range", "reviews", type_="check")
    # Возврат к NOT NULL возможен только без отзывов о неявке — они несовместимы со старой схемой.
    op.execute("DELETE FROM reviews WHERE rating IS NULL")
    op.alter_column("reviews", "rating", existing_type=sa.Integer(), nullable=False)
    op.create_check_constraint(
        "ck_reviews_rating_range", "reviews", "rating >= 1 AND rating <= 5"
    )
    op.drop_column("reviews", "attended")
    op.drop_column("users", "no_show_count")
