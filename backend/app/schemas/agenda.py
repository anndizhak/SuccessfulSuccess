"""Pydantic request/response models for a meeting's agenda."""

import json
import uuid
from datetime import date
from typing import Any

from pydantic import BaseModel, ConfigDict, Field, field_validator

MAX_AGENDA_ITEMS = 50
MAX_ACTION_ITEMS = 50
MAX_SUGGESTION_BYTES = 50_000


def _required_text(value: str) -> str:
    stripped = value.strip()
    if not stripped:
        raise ValueError("must not be blank")
    return stripped


def _optional_text(value: str | None) -> str | None:
    if value is None:
        return None
    return value.strip() or None


class AgendaItemIn(BaseModel):
    topic: str = Field(min_length=1, max_length=300)
    owner: str | None = Field(default=None, max_length=200)
    minutes: int | None = Field(default=None, ge=1, le=480)

    _topic = field_validator("topic")(_required_text)
    _owner = field_validator("owner")(_optional_text)


class ActionItemIn(BaseModel):
    task: str = Field(min_length=1, max_length=500)
    owner: str | None = Field(default=None, max_length=200)
    due: date | None = None

    _task = field_validator("task")(_required_text)
    _owner = field_validator("owner")(_optional_text)


class AiSuggestion(BaseModel):
    """What the parser suggested, stored as it was, next to what was saved."""

    model: str = Field(min_length=1, max_length=100)
    prompt_version: str = Field(min_length=1, max_length=50)
    agenda: dict[str, Any]

    @field_validator("agenda")
    @classmethod
    def _bounded(cls, value: dict[str, Any]) -> dict[str, Any]:
        if len(json.dumps(value)) > MAX_SUGGESTION_BYTES:
            raise ValueError(f"must be at most {MAX_SUGGESTION_BYTES} bytes of JSON")
        return value


class AgendaSave(BaseModel):
    """The whole agenda of a meeting. Saving replaces what was there."""

    items: list[AgendaItemIn] = Field(default_factory=list, max_length=MAX_AGENDA_ITEMS)
    action_items: list[ActionItemIn] = Field(default_factory=list, max_length=MAX_ACTION_ITEMS)
    # Present when the agenda started from a parsed suggestion; null when typed by hand.
    ai_suggestion: AiSuggestion | None = None


class AgendaItemRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    topic: str
    owner: str | None
    minutes: int | None
    position: int


class ActionItemRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: uuid.UUID
    task: str
    owner: str | None
    due: date | None
    position: int


class AgendaRead(BaseModel):
    meeting_id: uuid.UUID
    items: list[AgendaItemRead]
    action_items: list[ActionItemRead]
    ai_suggestion: AiSuggestion | None
