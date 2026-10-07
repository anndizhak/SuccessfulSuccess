"use client"

import { LogIn, LogOut } from "lucide-react"
import { useAuth } from "react-oidc-context"

import { Button } from "@/components/ui/button"
import { Skeleton } from "@/components/ui/skeleton"
import { cognitoLogoutUrl } from "@/lib/auth"

/** Sign in, or the signed-in user's email and Sign out. Needs SignInProvider. */
export function AuthControls() {
  const auth = useAuth()

  if (auth.isLoading) {
    return <Skeleton className="h-8 w-24 rounded-full" />
  }

  if (auth.isAuthenticated) {
    const email = auth.user?.profile.email

    const signOut = async () => {
      // Forget the tokens here, then end the session on Cognito's side too,
      // or the next sign-in would skip the login page.
      await auth.removeUser()
      window.location.assign(cognitoLogoutUrl())
    }

    return (
      <div className="flex min-w-0 items-center gap-2">
        <span
          className="text-muted-foreground hidden max-w-52 truncate text-sm sm:inline"
          title={email}
        >
          {email}
        </span>
        <Button variant="outline" size="sm" onClick={signOut}>
          <LogOut className="size-4" aria-hidden />
          <span className="hidden sm:inline">Sign out</span>
        </Button>
      </div>
    )
  }

  return (
    <Button variant="outline" size="sm" asChild>
      <a href="/login/">
        <LogIn className="size-4" aria-hidden />
        Sign in
      </a>
    </Button>
  )
}
