"use client"

import { useEffect, useRef } from "react"
import { useAuth } from "react-oidc-context"

import { AuthStatusPage } from "@/components/auth-status-page"
import { authEnabled } from "@/lib/auth"

/**
 * Starts the sign-in from the site, so the library can store its random state
 * and PKCE verifier before handing over to Cognito's managed login (email +
 * password, or Continue with Google). A hand-copied Cognito URL would sign the
 * user in, but the callback would then have no matching state to accept.
 */
export function LoginRedirect() {
  if (!authEnabled) {
    return (
      <AuthStatusPage title="Sign-in is not set up">
        This build was made without the auth stack&apos;s settings.
      </AuthStatusPage>
    )
  }
  return <StartSignIn />
}

function StartSignIn() {
  const auth = useAuth()
  const started = useRef(false)

  useEffect(() => {
    if (auth.isLoading || started.current) return
    started.current = true
    if (auth.isAuthenticated) {
      window.location.replace("/")
      return
    }
    void auth.signinRedirect({ state: { returnTo: "/" } })
  }, [auth])

  if (auth.error) {
    return (
      <AuthStatusPage title="Could not start sign-in">
        {auth.error.message}{" "}
        <a href="/login/" className="text-primary underline">
          Try again
        </a>
      </AuthStatusPage>
    )
  }

  return <AuthStatusPage title="Redirecting to sign-in…" />
}
