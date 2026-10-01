import {
  EventType,
  InteractionRequiredAuthError,
  PublicClientApplication,
  type AuthenticationResult,
} from '@azure/msal-browser'

// Sign-in with Microsoft Entra ID (see AUTH.md). The values are public identifiers
// (not secrets) from `terraform -chdir=infra/identity output -raw webapp_env`,
// kept in src/WebApp/.env.
const tenantId = import.meta.env.VITE_AUTH_TENANT_ID
const clientId = import.meta.env.VITE_AUTH_CLIENT_ID

// Each API is its own token audience, so the browser holds one access token per
// API — the matching scope is chosen from the request path in api.ts.
export const apiScopes = {
  candidates: import.meta.env.VITE_API_SCOPE_CANDIDATES,
  jobs: import.meta.env.VITE_API_SCOPE_JOBS,
  applications: import.meta.env.VITE_API_SCOPE_APPLICATIONS,
}

// Must match a redirect URI registered on the web app (infra/identity, with the
// trailing slash): http://localhost:5173/, http://localhost:5100/, https://ats.harsingh.com/
const appRoot = `${window.location.origin}/`

export const msal = new PublicClientApplication({
  auth: {
    clientId,
    authority: `https://login.microsoftonline.com/${tenantId}`,
    redirectUri: appRoot,
    postLogoutRedirectUri: appRoot,
  },
  // Per-tab sign-in that ends with the tab — a sensible default for a back-office app.
  cache: { cacheLocation: 'sessionStorage' },
})

// The signed-in account every token request is made for. MsalProvider processes
// the redirect back from Entra; this keeps the "active" account in step with it.
msal.addEventCallback((event) => {
  if (event.eventType === EventType.LOGIN_SUCCESS && event.payload) {
    msal.setActiveAccount((event.payload as AuthenticationResult).account)
  }
})

export async function initializeAuth(): Promise<void> {
  await msal.initialize()
  if (!msal.getActiveAccount()) {
    const [account] = msal.getAllAccounts()
    if (account) msal.setActiveAccount(account)
  }
}

// An access token for one API. Silent when possible (cached, or refreshed with
// the refresh token); otherwise a full-page redirect to Entra.
export async function getAccessToken(scope: string): Promise<string> {
  const account = msal.getActiveAccount()
  if (!account) throw new Error('You are signed out. Please sign in again.')
  try {
    const result = await msal.acquireTokenSilent({ scopes: [scope], account })
    return result.accessToken
  } catch (error) {
    if (error instanceof InteractionRequiredAuthError) {
      await msal.acquireTokenRedirect({ scopes: [scope], account })
    }
    throw error
  }
}
