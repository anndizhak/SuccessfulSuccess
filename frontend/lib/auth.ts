import { WebStorageStateStore, type UserManagerSettings } from "oidc-client-ts"

// Public values from the auth stack's outputs, baked in at build time like the
// API URL. None of them is a secret: the client is public and uses PKCE.
const authority = process.env.NEXT_PUBLIC_COGNITO_AUTHORITY ?? ""
const clientId = process.env.NEXT_PUBLIC_COGNITO_CLIENT_ID ?? ""
const cognitoDomain = (process.env.NEXT_PUBLIC_COGNITO_DOMAIN ?? "").replace(
  /\/+$/,
  ""
)

/** Sign-in is built in only when the build was given the auth stack's outputs. */
export const authEnabled = Boolean(authority && clientId && cognitoDomain)

/**
 * Must match a callback URL registered in infra/auth.yml exactly, trailing
 * slash included: the static export serves every route as a folder.
 */
export const CALLBACK_PATH = "/auth/callback/"

const origin = () =>
  typeof window === "undefined" ? "" : window.location.origin

/**
 * The redirect URI follows the origin the page was loaded from, so one build
 * works on CloudFront, on a custom domain and on localhost, as long as each of
 * them is a registered callback URL.
 */
export function oidcSettings(): UserManagerSettings {
  return {
    authority,
    client_id: clientId,
    redirect_uri: `${origin()}${CALLBACK_PATH}`,
    response_type: "code",
    scope: "openid email profile",
    // Keep the session across tabs and reloads. During the static build there
    // is no window, and oidc-client-ts falls back to memory on its own.
    userStore:
      typeof window === "undefined"
        ? undefined
        : new WebStorageStateStore({ store: window.localStorage }),
  }
}

/**
 * Cognito has no OIDC end-session endpoint: signing out of the managed login
 * means sending the browser to its own /logout with a registered logout URL.
 */
export function cognitoLogoutUrl(): string {
  const params = new URLSearchParams({
    client_id: clientId,
    logout_uri: `${origin()}/`,
  })
  return `${cognitoDomain}/logout?${params}`
}

/** Only same-site paths, so the sign-in state cannot redirect off the site. */
export function safeReturnPath(value: unknown): string {
  return typeof value === "string" && /^\/(?!\/)/.test(value) ? value : "/"
}
