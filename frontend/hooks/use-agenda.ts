"use client"

import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query"

import { getAgenda, saveAgenda } from "@/lib/api"
import type { AgendaSaveInput } from "@/lib/types"

export const agendaKey = (meetingId: string) => ["agenda", meetingId] as const

export function useAgenda(meetingId: string, enabled = true) {
  return useQuery({
    queryKey: agendaKey(meetingId),
    queryFn: () => getAgenda(meetingId),
    enabled,
  })
}

export function useSaveAgenda(meetingId: string) {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: (payload: AgendaSaveInput) => saveAgenda(meetingId, payload),
    onSuccess: (agenda) =>
      queryClient.setQueryData(agendaKey(meetingId), agenda),
  })
}
