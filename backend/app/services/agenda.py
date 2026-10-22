"""Business rules for a meeting's agenda: read it, and replace it as a whole."""

import uuid

from sqlalchemy.ext.asyncio import AsyncSession

from app.repositories.agenda import AgendaRepository
from app.repositories.meeting import MeetingRepository
from app.schemas.agenda import AgendaRead, AgendaSave, AiSuggestion
from app.services.meeting import MeetingNotFoundError


class AgendaService:
    def __init__(self, session: AsyncSession) -> None:
        self.meetings = MeetingRepository(session)
        self.repo = AgendaRepository(session)

    async def get(self, meeting_id: uuid.UUID) -> AgendaRead:
        meeting = await self.meetings.get(meeting_id)
        if meeting is None:
            raise MeetingNotFoundError(meeting_id)
        return AgendaRead(
            meeting_id=meeting.id,
            items=await self.repo.items(meeting.id),
            action_items=await self.repo.action_items(meeting.id),
            ai_suggestion=(
                AiSuggestion.model_validate(meeting.agenda_ai_suggestion)
                if meeting.agenda_ai_suggestion
                else None
            ),
        )

    async def save(self, meeting_id: uuid.UUID, payload: AgendaSave) -> AgendaRead:
        meeting = await self.meetings.get(meeting_id)
        if meeting is None:
            raise MeetingNotFoundError(meeting_id)
        await self.repo.replace(meeting, payload)
        return await self.get(meeting_id)
