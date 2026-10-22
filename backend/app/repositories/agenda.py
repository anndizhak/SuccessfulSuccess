"""Database access for agendas. No HTTP concerns live here."""

import uuid

from sqlalchemy import delete, select
from sqlalchemy.ext.asyncio import AsyncSession

from app.models import ActionItem, AgendaItem, Meeting
from app.schemas.agenda import AgendaSave


class AgendaRepository:
    def __init__(self, session: AsyncSession) -> None:
        self.session = session

    async def items(self, meeting_id: uuid.UUID) -> list[AgendaItem]:
        result = await self.session.scalars(
            select(AgendaItem)
            .where(AgendaItem.meeting_id == meeting_id)
            .order_by(AgendaItem.position)
        )
        return list(result)

    async def action_items(self, meeting_id: uuid.UUID) -> list[ActionItem]:
        result = await self.session.scalars(
            select(ActionItem)
            .where(ActionItem.meeting_id == meeting_id)
            .order_by(ActionItem.position)
        )
        return list(result)

    async def replace(self, meeting: Meeting, payload: AgendaSave) -> None:
        """Swap the whole agenda in one transaction: no half-saved agenda."""
        await self.session.execute(delete(AgendaItem).where(AgendaItem.meeting_id == meeting.id))
        await self.session.execute(delete(ActionItem).where(ActionItem.meeting_id == meeting.id))
        self.session.add_all(
            AgendaItem(
                meeting_id=meeting.id,
                topic=item.topic,
                owner=item.owner,
                minutes=item.minutes,
                position=index,
            )
            for index, item in enumerate(payload.items)
        )
        self.session.add_all(
            ActionItem(
                meeting_id=meeting.id,
                task=item.task,
                owner=item.owner,
                due=item.due,
                position=index,
            )
            for index, item in enumerate(payload.action_items)
        )
        meeting.agenda_ai_suggestion = (
            payload.ai_suggestion.model_dump(mode="json") if payload.ai_suggestion else None
        )
        await self.session.commit()
