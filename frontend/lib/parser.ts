// Client for the agenda parser (infra/ai.yml). It only suggests: saving goes
// through the main API's agenda endpoint, never through this URL.

export const PARSER_URL = (process.env.NEXT_PUBLIC_PARSER_URL ?? "").replace(
  /\/+$/,
  ""
)
export const parserEnabled = Boolean(PARSER_URL)
export const MAX_PASTE_CHARS = 10_000

/** Mirrors ParsedAgenda in backend/app/ai/agenda.py. */
export type ParsedAgenda = {
  title: string | null
  starts_at: string | null
  duration_minutes: number | null
  items: { topic: string; owner: string | null; minutes: number | null }[]
  action_items: { task: string; owner: string | null; due: string | null }[]
  language: string
}

export type ParseResult = {
  agenda: ParsedAgenda
  model: string
  prompt_version: string
}

export class ParseError extends Error {
  constructor(
    message: string,
    readonly kind:
      | "unauthorized"
      | "too_long"
      | "no_agenda"
      | "busy"
      | "network"
      | "cancelled"
      | "failed"
  ) {
    super(message)
    this.name = "ParseError"
  }
}

const MESSAGES: Record<number, [ParseError["kind"], string]> = {
  401: ["unauthorized", "Your session has expired. Sign in again."],
  413: ["too_long", "The text is too long: at most 10,000 characters."],
  422: ["no_agenda", "Could not find an agenda in this text."],
  429: ["busy", "The AI service is busy. Try again in a moment."],
}

/** The user's own date and time zone: their "Monday" is not the server's. */
function todayHere(): { today: string; tz: string } {
  const tz = Intl.DateTimeFormat().resolvedOptions().timeZone
  // en-CA formats as YYYY-MM-DD.
  const today = new Intl.DateTimeFormat("en-CA", { timeZone: tz }).format(
    new Date()
  )
  return { today, tz }
}

export async function parseAgenda(
  text: string,
  accessToken: string,
  signal: AbortSignal
): Promise<ParseResult> {
  let response: Response
  try {
    response = await fetch(PARSER_URL, {
      method: "POST",
      headers: {
        "content-type": "application/json",
        authorization: `Bearer ${accessToken}`,
      },
      body: JSON.stringify({ text, ...todayHere() }),
      signal,
    })
  } catch (error) {
    if (signal.aborted || (error as Error).name === "AbortError") {
      throw new ParseError("Cancelled.", "cancelled")
    }
    throw new ParseError(
      "Could not reach the AI service. Check your connection.",
      "network"
    )
  }
  if (response.ok) return (await response.json()) as ParseResult

  const [kind, message] = MESSAGES[response.status] ?? [
    "failed",
    "The AI service failed. Type the agenda by hand.",
  ]
  throw new ParseError(message, kind)
}
