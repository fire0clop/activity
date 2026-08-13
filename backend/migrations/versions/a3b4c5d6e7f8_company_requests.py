"""«Ищу компанию»: таблицы company_requests и request_supports

Revision ID: a3b4c5d6e7f8
Revises: f2a3b4c5d6e7
Create Date: 2026-08-15
"""
from collections.abc import Sequence

import geoalchemy2
import sqlalchemy as sa
from alembic import op

revision: str = "a3b4c5d6e7f8"
down_revision: str | None = "f2a3b4c5d6e7"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "company_requests",
        sa.Column("id", sa.Uuid(as_uuid=True), primary_key=True),
        sa.Column("author_id", sa.Uuid(as_uuid=True),
                  sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
        sa.Column("category", sa.String(60), nullable=False),
        sa.Column("text", sa.String(500), nullable=True),
        sa.Column(
            "location",
            geoalchemy2.types.Geography(geometry_type="POINT", srid=4326),
            nullable=False,
        ),
        sa.Column("latitude", sa.Float(), nullable=False),
        sa.Column("longitude", sa.Float(), nullable=False),
        sa.Column("area", sa.String(200), nullable=True),
        sa.Column("radius_km", sa.Float(), server_default="10", nullable=False),
        sa.Column("when_window", sa.String(16), nullable=False),
        sa.Column("status", sa.String(16), server_default="open", nullable=False),
        sa.Column("fulfilled_event_id", sa.Uuid(as_uuid=True),
                  sa.ForeignKey("events.id", ondelete="SET NULL"), nullable=True),
        sa.Column("expires_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True),
                  server_default=sa.func.now(), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True),
                  server_default=sa.func.now(), nullable=False),
        sa.CheckConstraint(
            "latitude >= -90 AND latitude <= 90 AND longitude >= -180 AND longitude <= 180",
            name="ck_requests_coords_range",
        ),
        sa.CheckConstraint(
            "when_window IN ('today', 'tomorrow', 'weekend', 'week')",
            name="ck_requests_when_window",
        ),
        sa.CheckConstraint("radius_km > 0 AND radius_km <= 100", name="ck_requests_radius"),
    )
    op.create_index("ix_company_requests_author_id", "company_requests", ["author_id"])
    op.create_index("ix_company_requests_category", "company_requests", ["category"])
    op.create_index("ix_company_requests_status", "company_requests", ["status"])
    op.create_index("ix_company_requests_expires_at", "company_requests", ["expires_at"])

    op.create_table(
        "request_supports",
        sa.Column("id", sa.Uuid(as_uuid=True), primary_key=True),
        sa.Column("request_id", sa.Uuid(as_uuid=True),
                  sa.ForeignKey("company_requests.id", ondelete="CASCADE"), nullable=False),
        sa.Column("user_id", sa.Uuid(as_uuid=True),
                  sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True),
                  server_default=sa.func.now(), nullable=False),
        sa.Column("updated_at", sa.DateTime(timezone=True),
                  server_default=sa.func.now(), nullable=False),
        sa.UniqueConstraint("request_id", "user_id", name="uq_request_support"),
    )
    op.create_index("ix_request_supports_request_id", "request_supports", ["request_id"])
    op.create_index("ix_request_supports_user_id", "request_supports", ["user_id"])


def downgrade() -> None:
    op.drop_table("request_supports")
    op.drop_index("ix_company_requests_expires_at", table_name="company_requests")
    op.drop_index("ix_company_requests_status", table_name="company_requests")
    op.drop_index("ix_company_requests_category", table_name="company_requests")
    op.drop_index("ix_company_requests_author_id", table_name="company_requests")
    op.drop_table("company_requests")
