"""ORM models for a meeting's agenda: the topics to discuss and the follow-ups."""

import uuid
from datetime import date

from sqlalchemy import Date, ForeignKey, Index, Integer, String
from sqlalchemy.dialects.postgresql import UUID as PgUUID
from sqlalchemy.orm import Mapped, mapped_column

from app.db import Base


class AgendaItem(Base):
    __tablename__ = "agenda_items"
    __table_args__ = (Index("ix_agenda_items_meeting_id", "meeting_id"),)

    id: Mapped[uuid.UUID] = mapped_column(
        PgUUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    meeting_id: Mapped[uuid.UUID] = mapped_column(
        PgUUID(as_uuid=True), ForeignKey("meetings.id", ondelete="CASCADE"), nullable=False
    )
    topic: Mapped[str] = mapped_column(String(300), nullable=False)
    owner: Mapped[str | None] = mapped_column(String(200), nullable=True)
    minutes: Mapped[int | None] = mapped_column(Integer, nullable=True)
    position: Mapped[int] = mapped_column(Integer, nullable=False, default=0)


class ActionItem(Base):
    __tablename__ = "action_items"
    __table_args__ = (Index("ix_action_items_meeting_id", "meeting_id"),)

    id: Mapped[uuid.UUID] = mapped_column(
        PgUUID(as_uuid=True), primary_key=True, default=uuid.uuid4
    )
    meeting_id: Mapped[uuid.UUID] = mapped_column(
        PgUUID(as_uuid=True), ForeignKey("meetings.id", ondelete="CASCADE"), nullable=False
    )
    task: Mapped[str] = mapped_column(String(500), nullable=False)
    owner: Mapped[str | None] = mapped_column(String(200), nullable=True)
    due: Mapped[date | None] = mapped_column(Date, nullable=True)
    position: Mapped[int] = mapped_column(Integer, nullable=False, default=0)
