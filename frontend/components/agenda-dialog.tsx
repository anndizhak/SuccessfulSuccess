"use client"

import { ListChecks } from "lucide-react"
import { useState } from "react"
import { toast } from "sonner"

import {
  AgendaForm,
  toFormValues,
  toPayload,
  type AgendaFormValues,
} from "@/components/agenda-form"
import { PasteAgenda } from "@/components/paste-agenda"
import { Alert, AlertDescription } from "@/components/ui/alert"
import { Button } from "@/components/ui/button"
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog"
import { Skeleton } from "@/components/ui/skeleton"
import { useAgenda, useSaveAgenda } from "@/hooks/use-agenda"
import { ApiError } from "@/lib/api"
import { authEnabled } from "@/lib/auth"
import { parserEnabled, type ParseResult } from "@/lib/parser"
import type { Meeting } from "@/lib/types"

/** A parsed agenda as form values, and the paths of the fields the model filled. */
function fromSuggestion(result: ParseResult): {
  values: AgendaFormValues
  suggested: Set<string>
} {
  const suggested = new Set<string>()
  const filled = (path: string, value: unknown) => {
    if (value !== null && value !== undefined && value !== "") {
      suggested.add(path)
    }
  }
  const { agenda } = result
  agenda.items.forEach((item, i) => {
    filled(`items.${i}.topic`, item.topic)
    filled(`items.${i}.owner`, item.owner)
    filled(`items.${i}.minutes`, item.minutes)
  })
  agenda.action_items.forEach((item, i) => {
    filled(`action_items.${i}.task`, item.task)
    filled(`action_items.${i}.owner`, item.owner)
    filled(`action_items.${i}.due`, item.due)
  })
  return {
    values: {
      items: agenda.items.map((item) => ({
        topic: item.topic,
        owner: item.owner ?? "",
        minutes: item.minutes == null ? "" : String(item.minutes),
      })),
      action_items: agenda.action_items.map((item) => ({
        task: item.task,
        owner: item.owner ?? "",
        due: item.due ?? "",
      })),
    },
    suggested,
  }
}

/** The "Agenda" button on a meeting card, and the dialog it opens. */
export function AgendaDialog({ meeting }: { meeting: Meeting }) {
  const [open, setOpen] = useState(false)
  // Fetched only once the dialog is opened, not for every card on the page.
  const agenda = useAgenda(meeting.id, open)
  const save = useSaveAgenda(meeting.id)
  // The model's suggestion, while the form shows it; null for a typed agenda.
  const [suggestion, setSuggestion] = useState<ParseResult | null>(null)
  const [parsedAt, setParsedAt] = useState(0)

  const openChange = (next: boolean) => {
    setOpen(next)
    if (!next) setSuggestion(null)
  }

  const prefill = suggestion ? fromSuggestion(suggestion) : null
  const mentioned = suggestion
    ? [
        suggestion.agenda.title && `title “${suggestion.agenda.title}”`,
        suggestion.agenda.starts_at && `starts ${suggestion.agenda.starts_at}`,
        suggestion.agenda.duration_minutes &&
          `${suggestion.agenda.duration_minutes} min`,
      ].filter(Boolean)
    : []

  return (
    <>
      <Button variant="outline" size="sm" onClick={() => setOpen(true)}>
        <ListChecks className="size-4" aria-hidden />
        Agenda
      </Button>
      <Dialog open={open} onOpenChange={openChange}>
        <DialogContent className="max-h-[90vh] overflow-y-auto sm:max-w-2xl">
          <DialogHeader>
            <DialogTitle>Agenda — {meeting.name}</DialogTitle>
            <DialogDescription>
              The topics to discuss and the follow-ups. Saving replaces the
              previous agenda.
            </DialogDescription>
          </DialogHeader>

          {authEnabled && parserEnabled ? (
            <PasteAgenda
              onParsed={(result) => {
                setSuggestion(result)
                setParsedAt(Date.now())
                toast.success("The form is filled in. Check it, then save.")
              }}
            />
          ) : null}

          {suggestion ? (
            <Alert>
              <AlertDescription className="flex flex-wrap items-center gap-x-2">
                <span>
                  Suggested by {suggestion.model} ({suggestion.prompt_version}
                  ). Fields marked <strong>suggested</strong> came from the AI:
                  check them before saving.
                  {mentioned.length
                    ? ` The text also mentions ${mentioned.join(", ")}.`
                    : ""}
                </span>
                <Button
                  type="button"
                  variant="link"
                  size="sm"
                  className="h-auto p-0"
                  onClick={() => setSuggestion(null)}
                >
                  Discard suggestion
                </Button>
              </AlertDescription>
            </Alert>
          ) : null}

          {agenda.isPending ? (
            <div className="space-y-3">
              <Skeleton className="h-9 w-full" />
              <Skeleton className="h-9 w-full" />
            </div>
          ) : agenda.isError ? (
            <Alert variant="destructive">
              <AlertDescription>
                Could not load the agenda: {agenda.error.message}
              </AlertDescription>
            </Alert>
          ) : (
            <AgendaForm
              // A fresh form for the saved agenda, or for each new suggestion.
              key={prefill ? `suggestion-${parsedAt}` : agenda.dataUpdatedAt}
              defaultValues={prefill?.values ?? toFormValues(agenda.data)}
              suggested={prefill?.suggested}
              onCancel={() => openChange(false)}
              onSave={async (values) => {
                try {
                  await save.mutateAsync({
                    ...toPayload(values),
                    // What the model suggested, kept next to what was saved:
                    // the difference is the parser's quality signal.
                    ai_suggestion: suggestion
                      ? {
                          model: suggestion.model,
                          prompt_version: suggestion.prompt_version,
                          agenda: suggestion.agenda,
                        }
                      : null,
                  })
                } catch (error) {
                  toast.error(
                    error instanceof ApiError
                      ? error.message
                      : "Could not save the agenda."
                  )
                  throw error
                }
                toast.success("Agenda saved")
                openChange(false)
              }}
            />
          )}
        </DialogContent>
      </Dialog>
    </>
  )
}
