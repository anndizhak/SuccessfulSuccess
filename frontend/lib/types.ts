// Mirrors the Pydantic schemas in backend/app/schemas/meeting.py.

export type Participant = {
  id: string
  name: string
  email: string | null
  position: number
}

export type Meeting = {
  id: string
  name: string
  description: string | null
  location: string | null
  starts_at: string
  ends_at: string
  participants: Participant[]
  created_at: string
  updated_at: string
}

export type MeetingList = {
  items: Meeting[]
  total: number
  limit: number
  offset: number
  date: string
}

export type ParticipantInput = {
  name: string
  email?: string | null
}

export type MeetingCreateInput = {
  name: string
  description?: string | null
  location?: string | null
  starts_at: string
  ends_at: string
  participants: ParticipantInput[]
}

// Mirrors backend/app/schemas/agenda.py.

export type AgendaItemInput = {
  topic: string
  owner?: string | null
  minutes?: number | null
}

export type ActionItemInput = {
  task: string
  owner?: string | null
  due?: string | null // YYYY-MM-DD
}

/** What the parser suggested, stored next to the agenda that was saved. */
export type AiSuggestion = {
  model: string
  prompt_version: string
  agenda: Record<string, unknown>
}

export type AgendaSaveInput = {
  items: AgendaItemInput[]
  action_items: ActionItemInput[]
  ai_suggestion?: AiSuggestion | null
}

export type Agenda = {
  meeting_id: string
  items: (Required<AgendaItemInput> & { id: string; position: number })[]
  action_items: (Required<ActionItemInput> & { id: string; position: number })[]
  ai_suggestion: AiSuggestion | null
}

export type ApiErrorDetail = {
  field: string
  message: string
}

export type ApiErrorBody = {
  error: {
    code: string
    message: string
    details: ApiErrorDetail[]
  }
}
