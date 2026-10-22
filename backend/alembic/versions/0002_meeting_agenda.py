"""meeting agenda: agenda items, action items and the AI suggestion

Revision ID: 0002
Revises: 0001
Create Date: 2026-10-21
"""

import sqlalchemy as sa
from sqlalchemy.dialects import postgresql

from alembic import op

revision = "0002"
down_revision = "0001"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "agenda_items",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column(
            "meeting_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("meetings.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column("topic", sa.String(300), nullable=False),
        sa.Column("owner", sa.String(200), nullable=True),
        sa.Column("minutes", sa.Integer(), nullable=True),
        sa.Column("position", sa.Integer(), nullable=False, server_default="0"),
    )
    op.create_index("ix_agenda_items_meeting_id", "agenda_items", ["meeting_id"])

    op.create_table(
        "action_items",
        sa.Column("id", postgresql.UUID(as_uuid=True), primary_key=True),
        sa.Column(
            "meeting_id",
            postgresql.UUID(as_uuid=True),
            sa.ForeignKey("meetings.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column("task", sa.String(500), nullable=False),
        sa.Column("owner", sa.String(200), nullable=True),
        sa.Column("due", sa.Date(), nullable=True),
        sa.Column("position", sa.Integer(), nullable=False, server_default="0"),
    )
    op.create_index("ix_action_items_meeting_id", "action_items", ["meeting_id"])

    op.add_column(
        "meetings",
        sa.Column("agenda_ai_suggestion", postgresql.JSONB(), nullable=True),
    )


def downgrade() -> None:
    op.drop_column("meetings", "agenda_ai_suggestion")
    op.drop_index("ix_action_items_meeting_id", table_name="action_items")
    op.drop_table("action_items")
    op.drop_index("ix_agenda_items_meeting_id", table_name="agenda_items")
    op.drop_table("agenda_items")
