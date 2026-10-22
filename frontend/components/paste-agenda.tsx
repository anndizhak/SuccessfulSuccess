"use client"

import { Loader2, Sparkles, X } from "lucide-react"
import { useEffect, useRef, useState } from "react"
import { useAuth } from "react-oidc-context"

import { Alert, AlertDescription } from "@/components/ui/alert"
import { Button } from "@/components/ui/button"
import { Label } from "@/components/ui/label"
import { Textarea } from "@/components/ui/textarea"
import {
  MAX_PASTE_CHARS,
  ParseError,
  parseAgenda,
  type ParseResult,
} from "@/lib/parser"

/**
 * "Paste an agenda": text in, a suggested agenda out. The suggestion only
 * pre-fills the normal form; the person checks it and presses Save.
 * Needs SignInProvider (every parse costs money, so it needs a signed-in user).
 */
export function PasteAgenda({
  onParsed,
}: {
  onParsed: (result: ParseResult) => void
}) {
  const auth = useAuth()
  const [text, setText] = useState("")
  const [error, setError] = useState<string | null>(null)
  const [running, setRunning] = useState(false)
  const [seconds, setSeconds] = useState(0)
  const controller = useRef<AbortController | null>(null)

  // Abandon a parse that is still running when the dialog closes.
  useEffect(() => () => controller.current?.abort(), [])

  if (!auth.isAuthenticated || !auth.user) {
    return (
      <p className="text-muted-foreground text-sm">
        <a href="/login/" className="text-primary underline">
          Sign in
        </a>{" "}
        to paste an agenda and let the AI fill in the form.
      </p>
    )
  }

  const parse = async () => {
    setError(null)
    setSeconds(0)
    setRunning(true)
    const abort = new AbortController()
    controller.current = abort
    const timer = setInterval(() => setSeconds((s) => s + 1), 1000)
    try {
      onParsed(await parseAgenda(text, auth.user!.access_token, abort.signal))
      setText("")
    } catch (caught) {
      if (caught instanceof ParseError && caught.kind === "cancelled") return
      setError(
        caught instanceof ParseError
          ? caught.message
          : "Something went wrong. Type the agenda by hand."
      )
    } finally {
      clearInterval(timer)
      controller.current = null
      setRunning(false)
    }
  }

  const tooLong = text.length > MAX_PASTE_CHARS

  return (
    <section className="tint-violet space-y-2 rounded-2xl p-4">
      <Label htmlFor="paste-agenda" className="font-semibold">
        <Sparkles className="size-4" aria-hidden />
        Paste an agenda
      </Label>
      <Textarea
        id="paste-agenda"
        rows={4}
        value={text}
        disabled={running}
        placeholder="Paste an email, a chat message or notes. The AI fills in the form below, and you check it before saving."
        onChange={(event) => setText(event.target.value)}
        className="bg-background"
      />
      <div className="flex flex-wrap items-center gap-2">
        {running ? (
          <>
            <span
              className="text-muted-foreground inline-flex items-center gap-2 text-sm"
              role="status"
            >
              <Loader2 className="size-4 animate-spin" aria-hidden />
              Reading your agenda… {seconds} s (usually 2–8 s)
            </span>
            <Button
              type="button"
              variant="outline"
              size="sm"
              onClick={() => controller.current?.abort()}
            >
              <X className="size-4" aria-hidden />
              Cancel
            </Button>
          </>
        ) : (
          <Button
            type="button"
            size="sm"
            disabled={!text.trim() || tooLong}
            onClick={parse}
          >
            <Sparkles className="size-4" aria-hidden />
            Parse
          </Button>
        )}
        <span
          className={`ml-auto text-xs tabular-nums ${tooLong ? "text-destructive" : "text-muted-foreground"}`}
        >
          {text.length.toLocaleString()} / {MAX_PASTE_CHARS.toLocaleString()}
        </span>
      </div>
      {error ? (
        <Alert variant="destructive">
          <AlertDescription>
            {error} You can always type the agenda below by hand.
          </AlertDescription>
        </Alert>
      ) : null}
    </section>
  )
}
