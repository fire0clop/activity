"""афиша: poster_events + связь events.poster_id

Revision ID: b4c5d6e7f8a9
Revises: a3b4c5d6e7f8
Create Date: 2026-08-16
"""
from collections.abc import Sequence

import geoalchemy2
import sqlalchemy as sa
from alembic import op

revision: str = "b4c5d6e7f8a9"
down_revision: str | None = "a3b4c5d6e7f8"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "poster_events",
        sa.Column("id", sa.Uuid(as_uuid=True), primary_key=True),
        sa.Column("title", sa.String(200), nullable=False),
        sa.Column("description", sa.String(), nullable=True),
        sa.Column("category", sa.String(60), nullable=True),
        sa.Column("starts_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("ends_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("venue", sa.String(200), nullable=True),
        sa.Column("address", sa.String(), nullable=True),
        sa.Column(
            "location",
            geoalchemy2.types.Geography(geometry_type="POINT", srid=4326),
            nullable=False,
        ),
        sa.Column("latitude", sa.Float(), nullable=False),
        sa.Column("longitude", sa.Float(), nullable=False),
        sa.Column("price_from", sa.Numeric(10, 2), nullable=True),
        sa.Column("is_free", sa.Boolean(), server_default="false", nullable=False),
        sa.Column("image_url", sa.String(), nullable=True),
        sa.Column("source_url", sa.String(), nullable=True),
        sa.Column("source_name", sa.String(120), nullable=True),
        sa.Column("status", sa.String(16), server_default="published", nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True),
                  server_default=sa.func.now(), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True),
                  server_default=sa.func.now(), nullable=False),
        sa.CheckConstraint(
            "latitude >= -90 AND latitude <= 90 AND longitude >= -180 AND longitude <= 180",
            name="ck_poster_coords_range",
        ),
        sa.CheckConstraint("status IN ('published', 'hidden')", name="ck_poster_status"),
    )
    op.create_index("ix_poster_events_category", "poster_events", ["category"])
    op.create_index("ix_poster_events_starts_at", "poster_events", ["starts_at"])
    op.create_index("ix_poster_events_status", "poster_events", ["status"])

    op.add_column(
        "events",
        sa.Column("poster_id", sa.Uuid(as_uuid=True), nullable=True),
    )
    op.create_foreign_key(
        "fk_events_poster_id", "events", "poster_events", ["poster_id"], ["id"],
        ondelete="SET NULL",
    )
    op.create_index("ix_events_poster_id", "events", ["poster_id"])


def downgrade() -> None:
    op.drop_index("ix_events_poster_id", table_name="events")
    op.drop_constraint("fk_events_poster_id", "events", type_="foreignkey")
    op.drop_column("events", "poster_id")
    op.drop_index("ix_poster_events_status", table_name="poster_events")
    op.drop_index("ix_poster_events_starts_at", table_name="poster_events")
    op.drop_index("ix_poster_events_category", table_name="poster_events")
    op.drop_table("poster_events")
