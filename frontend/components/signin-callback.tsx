"use client"

import { useAuth } from "react-oidc-context"

import { AuthStatusPage } from "@/components/auth-status-page"
import { authEnabled } from "@/lib/auth"

/**
 * Cognito sends the browser here with ?code=&state=. SignInProvider exchanges
 * the code for tokens and then leaves for the page the sign-in started from;
 * this page only shows progress, or the error if the exchange fails.
 */
export function SigninCallback() {
  if (!authEnabled) {
    return <AuthStatusPage title="Sign-in is not set up" />
  }
  return <CallbackStatus />
}

function CallbackStatus() {
  const auth = useAuth()

  if (auth.error) {
    return (
      <AuthStatusPage title="Sign-in failed">
        {auth.error.message}{" "}
        <a href="/login/" className="text-primary underline">
          Start again
        </a>
      </AuthStatusPage>
    )
  }

  return <AuthStatusPage title="Signing you in…" />
}
