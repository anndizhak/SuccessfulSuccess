# 6. Parse pasted agendas with an LLM, on the side of the write path

- Status: accepted
- Date: 2026-10-21

## Context

Agendas arrive as free text: an email from a manager, a chat message, a few
lines of notes, in Ukrainian or English. Typing them into the agenda form is
slow. We want **Paste an agenda**: the user pastes the text, a model turns it
into a structured agenda, the app shows the normal form pre-filled, and the
user checks it and presses Save. The model suggests; the person decides.

Constraints:

- **No NAT gateway.** The API runs in the VPC to reach Aurora and has no route
  to the internet (Labs 4–5). Bedrock is on the internet.
- **Cost.** Every parse costs tokens, so the endpoint must not be open to
  anyone, and the idle cost should stay at zero (a NAT gateway is ~$33 a month,
  a VPC interface endpoint ~$7.30 per zone).
- **Text from outside.** Pasted text can contain instructions ("ignore your
  instructions…"). It is data, never commands.
- **A model can be confidently wrong**, with a 200 status. Its output must be
  validated, and a person must confirm it before anything is stored.

## Decision

- **A separate parser function outside the VPC** (`infra/ai.yml`): the backend
  image with another handler (`app.ai.agenda_lambda.handler`), behind its own
  function URL. It needs Bedrock and Cognito's public keys, never the database,
  so outside the VPC it reaches both with no NAT and no endpoint, and costs
  nothing while unused.
- **The model never writes.** The parser receives text and returns JSON. Saving
  goes through the existing `POST /meetings/{id}/agenda` in the main API, with
  its validation and its database access, exactly as for a typed agenda.
- **Claude on Amazon Bedrock**, called with the user's text, today's date and
  time zone, and a `record_agenda` tool whose input schema is `ParsedAgenda`.
  The pasted text is delimited and the system prompt says it is data. The
  output is validated with Pydantic; one retry shows the model its validation
  error, then a clear error.
- **Model and API are configuration** (`PARSER_MODEL`, `PARSER_API`). The lab's
  choice is Claude Opus 5.5 through the Anthropic Messages API on
  `bedrock-mantle`. This account cannot use it yet, so the parser currently
  runs Claude Sonnet 4.5 through the Converse API; switching back is a
  redeploy, not a code change.
- **Signed-in users only.** The handler verifies the Cognito access token
  (signature against the pool's JWKS, expiry, issuer, client) and returns 401
  otherwise, before any model call. Texts over 10,000 characters get 413.
- **The suggestion is kept.** The save request carries what the model
  suggested, with the model and prompt version; the API stores it next to the
  saved agenda (`meetings.agenda_ai_suggestion`). The difference is the
  parser's quality signal.

## Alternatives considered

- **Call Bedrock from the API, through a VPC interface endpoint.** One
  function fewer, but ~$7.30 a month per availability zone even with no
  traffic, and the LLM call would sit inside the API that also writes to the
  database. Lost on idle cost and on keeping the model away from the write path.
- **The Claude API directly (api.anthropic.com) instead of Bedrock.** Newest
  models first and the same request shape, but an API key to store and rotate,
  a second bill outside AWS, and no IAM, CloudTrail or AWS Budgets around it.
  Lost on "no keys" and one bill.
- **A plain regular-expression parser.** Free, fast and deterministic, but it
  breaks on the first email with a greeting, a signature, another language or a
  relative date ("до п'ятниці", "next Tuesday after lunch"). Lost on the kind
  of text users actually paste.

## Consequences

- **Cost per parse:** ~1,360 input and ~300 output tokens, $0.0086 with Sonnet
  4.5 ($3 / $15 per million). With Opus 5.5 the same parse would be about
  $0.011; with Haiku 5.5 about $0.0003.
- **What is logged:** one JSON line per parse with the user (Cognito `sub`),
  model, API, prompt version, input and output tokens, attempts, latency and
  cost in dollars. The pasted text is not logged: it is the user's data.
- **When Bedrock is down or throttling**, the parser answers 429 or 502, the
  screen says so, and the user types the agenda by hand. Nothing else in the app
  depends on the parser: meetings, the agenda form, sign-in and the weekly
  report keep working.
- **Output varies between runs.** The same text gave `starts_at` as
  `2026-10-26 10:00` once and `Monday 10:00` once: the schema types it as a
  plain string. Tightening the schema is a prompt/schema version change
  (`agenda-v2`), measured against the stored suggestions.
- **Prompt injection is limited, not solved.** The model only ever sees the
  text the user pasted, and its output is a suggestion the user confirms; it
  cannot read other users' data or write anything.
