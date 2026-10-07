import { LoginRedirect } from "@/components/login-redirect"

export const metadata = {
  title: "Sign in — SuccessfulSuccess",
}

/** The URL to share: opening it goes straight to Cognito's sign-in page. */
export default function LoginPage() {
  return <LoginRedirect />
}
