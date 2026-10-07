import { CalendarDays } from "lucide-react"

/** Centered card for the /login/ and /auth/callback/ pages. */
export function AuthStatusPage({
  title,
  children,
}: {
  title: string
  children?: React.ReactNode
}) {
  return (
    <main className="flex flex-1 items-center justify-center p-6">
      <div className="bg-card w-full max-w-sm rounded-3xl p-8 text-center shadow-sm ring-1 ring-black/5">
        <span
          className="mx-auto mb-4 flex size-12 items-center justify-center rounded-full text-white"
          style={{
            backgroundImage:
              "linear-gradient(135deg, var(--canva-teal), var(--canva-blue) 45%, var(--canva-violet))",
          }}
        >
          <CalendarDays className="size-5" aria-hidden />
        </span>
        <h1 className="text-gradient-canva text-xl font-bold tracking-tight">
          {title}
        </h1>
        {children ? (
          <div className="text-muted-foreground mt-2 text-sm">{children}</div>
        ) : null}
      </div>
    </main>
  )
}
