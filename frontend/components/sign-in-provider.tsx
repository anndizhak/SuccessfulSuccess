"use client"

import type { User } from "oidc-client-ts"
import { AuthProvider } from "react-oidc-context"

import { authEnabled, oidcSettings, safeReturnPath } from "@/lib/auth"

const settings = authEnabled ? oidcSettings() : null

/**
 * Runs once Cognito has sent the browser back and the code has been exchanged
 * for tokens: leave the callback URL (and its ?code=&state=) for the page the
 * sign-in started from.
 */
function onSigninCallback(user: User | void) {
  const state = user?.state as { returnTo?: unknown } | undefined
  window.location.replace(safeReturnPath(state?.returnTo))
}

export function SignInProvider({ children }: { children: React.ReactNode }) {
  if (!settings) return <>{children}</>
  return (
    <AuthProvider {...settings} onSigninCallback={onSigninCallback}>
      {children}
    </AuthProvider>
  )
}
