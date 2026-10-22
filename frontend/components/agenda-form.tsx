"use client"

import { zodResolver } from "@hookform/resolvers/zod"
import { Plus, Trash2 } from "lucide-react"
import { useFieldArray, useForm, type FieldPath } from "react-hook-form"
import { z } from "zod"

import { Badge } from "@/components/ui/badge"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { ApiError } from "@/lib/api"
import type { Agenda, AgendaSaveInput } from "@/lib/types"

const blankOr = (schema: z.ZodString) =>
  z
    .string()
    .trim()
    .refine((v) => v === "" || schema.safeParse(v).success)

// Mirrors backend/app/schemas/agenda.py; the API validates again on save.
const formSchema = z.object({
  items: z
    .array(
      z.object({
        topic: z
          .string()
          .trim()
          .min(1, "Topic is required")
          .max(300, "Topic is too long"),
        owner: z.string().trim().max(200, "Owner is too long"),
        minutes: blankOr(z.string().regex(/^\d+$/)).refine(
          (v) => v === "" || (Number(v) >= 1 && Number(v) <= 480),
          "1–480 minutes"
        ),
      })
    )
    .max(50, "At most 50 topics"),
  action_items: z
    .array(
      z.object({
        task: z
          .string()
          .trim()
          .min(1, "Task is required")
          .max(500, "Task is too long"),
        owner: z.string().trim().max(200, "Owner is too long"),
        due: blankOr(z.string().regex(/^\d{4}-\d{2}-\d{2}$/)),
      })
    )
    .max(50, "At most 50 action items"),
})

export type AgendaFormValues = z.infer<typeof formSchema>

export const emptyItem = { topic: "", owner: "", minutes: "" }
export const emptyAction = { task: "", owner: "", due: "" }

/** The saved agenda as form values: numbers and nulls become strings. */
export function toFormValues(agenda: Agenda | undefined): AgendaFormValues {
  return {
    items: (agenda?.items ?? []).map((item) => ({
      topic: item.topic,
      owner: item.owner ?? "",
      minutes: item.minutes == null ? "" : String(item.minutes),
    })),
    action_items: (agenda?.action_items ?? []).map((item) => ({
      task: item.task,
      owner: item.owner ?? "",
      due: item.due ?? "",
    })),
  }
}

/** Form values as the API payload: empty fields become null. */
export function toPayload(
  values: AgendaFormValues
): Omit<AgendaSaveInput, "ai_suggestion"> {
  return {
    items: values.items.map((item) => ({
      topic: item.topic.trim(),
      owner: item.owner.trim() || null,
      minutes: item.minutes === "" ? null : Number(item.minutes),
    })),
    action_items: values.action_items.map((item) => ({
      task: item.task.trim(),
      owner: item.owner.trim() || null,
      due: item.due || null,
    })),
  }
}

export function AgendaForm({
  defaultValues,
  suggested = new Set<string>(),
  onSave,
  onCancel,
}: {
  defaultValues: AgendaFormValues
  /** Field paths (e.g. "items.0.topic") a model filled in, badged until edited. */
  suggested?: Set<string>
  /** Throws ApiError on a failed save; its field details are shown inline. */
  onSave: (values: AgendaFormValues) => Promise<void>
  onCancel: () => void
}) {
  const {
    control,
    register,
    handleSubmit,
    setError,
    formState: { errors, dirtyFields, isSubmitting },
  } = useForm<AgendaFormValues>({
    resolver: zodResolver(formSchema),
    defaultValues,
  })
  const items = useFieldArray({ control, name: "items" })
  const actions = useFieldArray({ control, name: "action_items" })

  const isSuggested = (path: string) => {
    if (!suggested.has(path)) return false
    const [list, index, field] = path.split(".")
    const dirty = (dirtyFields as Record<string, Record<string, unknown>[]>)[
      list
    ]?.[Number(index)]?.[field]
    return !dirty
  }

  const onSubmit = handleSubmit(async (values) => {
    try {
      await onSave(values)
    } catch (error) {
      if (error instanceof ApiError) {
        for (const detail of error.details) {
          setError(detail.field as FieldPath<AgendaFormValues>, {
            message: detail.message,
          })
        }
      }
      throw error
    }
  })

  return (
    <form
      onSubmit={(event) => onSubmit(event).catch(() => undefined)}
      className="space-y-6"
    >
      <section className="space-y-3">
        <div className="flex items-center justify-between">
          <h3 className="font-semibold">Topics</h3>
          <Button
            type="button"
            variant="outline"
            size="sm"
            onClick={() => items.append(emptyItem)}
          >
            <Plus className="size-4" aria-hidden />
            Add topic
          </Button>
        </div>
        {items.fields.length === 0 ? (
          <p className="text-muted-foreground text-sm">No topics yet.</p>
        ) : null}
        {items.fields.map((field, index) => (
          <div
            key={field.id}
            className="grid gap-2 sm:grid-cols-[1fr_9rem_5.5rem_auto]"
          >
            <FieldBox
              label="Topic"
              id={`items.${index}.topic`}
              error={errors.items?.[index]?.topic?.message}
              suggested={isSuggested(`items.${index}.topic`)}
            >
              <Input
                id={`items.${index}.topic`}
                {...register(`items.${index}.topic`)}
              />
            </FieldBox>
            <FieldBox
              label="Owner"
              id={`items.${index}.owner`}
              error={errors.items?.[index]?.owner?.message}
              suggested={isSuggested(`items.${index}.owner`)}
            >
              <Input
                id={`items.${index}.owner`}
                {...register(`items.${index}.owner`)}
              />
            </FieldBox>
            <FieldBox
              label="Minutes"
              id={`items.${index}.minutes`}
              error={errors.items?.[index]?.minutes?.message}
              suggested={isSuggested(`items.${index}.minutes`)}
            >
              <Input
                id={`items.${index}.minutes`}
                inputMode="numeric"
                {...register(`items.${index}.minutes`)}
              />
            </FieldBox>
            <RemoveButton
              label={`Remove topic ${index + 1}`}
              onClick={() => items.remove(index)}
            />
          </div>
        ))}
      </section>

      <section className="space-y-3">
        <div className="flex items-center justify-between">
          <h3 className="font-semibold">Action items</h3>
          <Button
            type="button"
            variant="outline"
            size="sm"
            onClick={() => actions.append(emptyAction)}
          >
            <Plus className="size-4" aria-hidden />
            Add action item
          </Button>
        </div>
        {actions.fields.length === 0 ? (
          <p className="text-muted-foreground text-sm">No action items yet.</p>
        ) : null}
        {actions.fields.map((field, index) => (
          <div
            key={field.id}
            className="grid gap-2 sm:grid-cols-[1fr_9rem_9.5rem_auto]"
          >
            <FieldBox
              label="Task"
              id={`action_items.${index}.task`}
              error={errors.action_items?.[index]?.task?.message}
              suggested={isSuggested(`action_items.${index}.task`)}
            >
              <Input
                id={`action_items.${index}.task`}
                {...register(`action_items.${index}.task`)}
              />
            </FieldBox>
            <FieldBox
              label="Owner"
              id={`action_items.${index}.owner`}
              error={errors.action_items?.[index]?.owner?.message}
              suggested={isSuggested(`action_items.${index}.owner`)}
            >
              <Input
                id={`action_items.${index}.owner`}
                {...register(`action_items.${index}.owner`)}
              />
            </FieldBox>
            <FieldBox
              label="Due"
              id={`action_items.${index}.due`}
              error={errors.action_items?.[index]?.due?.message}
              suggested={isSuggested(`action_items.${index}.due`)}
            >
              <Input
                id={`action_items.${index}.due`}
                type="date"
                {...register(`action_items.${index}.due`)}
              />
            </FieldBox>
            <RemoveButton
              label={`Remove action item ${index + 1}`}
              onClick={() => actions.remove(index)}
            />
          </div>
        ))}
      </section>

      <div className="flex justify-end gap-2">
        <Button type="button" variant="outline" onClick={onCancel}>
          Cancel
        </Button>
        <Button type="submit" disabled={isSubmitting}>
          {isSubmitting ? "Saving…" : "Save agenda"}
        </Button>
      </div>
    </form>
  )
}

function FieldBox({
  label,
  id,
  error,
  suggested,
  children,
}: {
  label: string
  id: string
  error?: string
  suggested: boolean
  children: React.ReactNode
}) {
  return (
    <div className="space-y-1">
      <div className="flex items-center gap-1.5">
        <Label htmlFor={id} className="text-xs">
          {label}
        </Label>
        {suggested ? (
          <Badge variant="secondary" className="h-4 px-1.5 text-[10px]">
            suggested
          </Badge>
        ) : null}
      </div>
      {children}
      {error ? (
        <p className="text-destructive text-xs" role="alert">
          {error}
        </p>
      ) : null}
    </div>
  )
}

function RemoveButton({
  label,
  onClick,
}: {
  label: string
  onClick: () => void
}) {
  return (
    <div className="flex items-end">
      <Button
        type="button"
        variant="ghost"
        size="icon"
        aria-label={label}
        onClick={onClick}
      >
        <Trash2 className="size-4" aria-hidden />
      </Button>
    </div>
  )
}
