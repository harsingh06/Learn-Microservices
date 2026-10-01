# Authentication & authorization

Users sign in with **Microsoft Entra ID**. Every microservice validates every
request itself and enforces its own role rules — including the calls
ApplicationService makes to CandidateService and JobService, which use the
**On-Behalf-Of** flow.

## Roles and what they may do

| Endpoint | Recruiter | HiringManager |
|---|---|---|
| `GET` candidates / jobs / applications | ✅ | ✅ |
| `POST`/`PUT` candidates, `POST`/`PUT` jobs | ✅ | ❌ 403 |
| `POST /applications` (submit) | ✅ | ❌ 403 |
| `PUT /applications/{id}/status` (review) | ❌ 403 | ✅ |
| `/health`, `/openapi/*`, `/scalar/*` | anonymous | anonymous |

- No token, or a token for another API → **401**. A valid token without the
  `access_as_user` scope or without the role → **403**.
- **Secure by default:** a fallback policy (signed in + scope) covers every endpoint
  that doesn't name a policy, so a new endpoint can't be accidentally public.
- The web UI hides what a role can't do (forms, the Apply page, status changes) —
  usability only; the APIs enforce the same rules regardless.

## How it works

```
                 ┌──────────── Entra ID (tenant hs060301outlook.onmicrosoft.com) ────────────┐
                 │ apps: ATS Web (SPA) · ATS Candidate API · ATS Job API · ATS Application API │
                 │ roles assigned per app: Recruiter / HiringManager                         │
                 └────────────────────────────────────────────────────────────────────────────┘
 ① sign in (redirect, PKCE)    ▲ ② ID token (name, roles) + one access token per API
                               │
 Browser (MSAL) ── aud=Candidate API ───────────────────────────► CandidateService  ┐ validate signature,
                ── aud=Job API ─────────────────────────────────► JobService        │ issuer, audience,
                ── aud=Application API ──► ApplicationService ───────────────────────┘ scope, role
                                              │ ③ On-Behalf-Of: "here's Ada's token, give me one for
                                              │    Candidate API" — signed with ITS OWN credential
                                              ▼
                                  token: aud=Candidate API, user=Ada, roles=Ada's,
                                         azp=ATS Application API ──► CandidateService
```

1. **Sign-in** — the web app redirects to Entra (auth code + PKCE, no secret in the
   browser). Only users assigned a role may sign in at all
   (`app_role_assignment_required`).
2. **Tokens** — each API is its own **audience**, so the browser asks for one access
   token per API (`src/WebApp/src/api.ts` picks the scope from the URL). Tokens are
   short-lived (~1 h) and refreshed silently.
3. **Validation** — every service checks the token itself with Microsoft.Identity.Web:
   Entra's signing keys, our tenant as issuer, **its own** client ID as audience,
   lifetime. Then its policies check the `access_as_user` scope and the role
   (`src/<Service>/Auth/AuthSetup.cs`).
4. **Service to service (On-Behalf-Of)** — ApplicationService doesn't forward the
   user's token (its audience is ApplicationService). It **exchanges** it with Entra
   for a token aimed at CandidateService / JobService, proving its own identity with
   a credential (client secret locally, managed identity in Azure). The new token
   carries the **user and their roles** *and* **which app is calling** (`azp`), and is
   only valid for that one API. It happens in an `HttpClient` handler
   (`AddMicrosoftIdentityUserAuthenticationHandler` in `Program.cs`), so the client
   classes don't change. Exchanged tokens are cached in memory per user and API.

### Why On-Behalf-Of (and not the alternatives)

| | Forward the user's token | Service's own identity | **On-Behalf-Of** |
|---|---|---|---|
| Downstream knows the user | ✅ | ❌ | ✅ |
| Downstream knows the calling service | ❌ | ✅ | ✅ |
| Token valid for one service only | ❌ (shared audience) | ✅ | ✅ |
| Works without a user (background jobs) | ❌ | ✅ | ❌ |
| Setup | minimal | medium | most |

A future message consumer (NotificationWorker) has no user, so it will use its own
identity (client credentials) — see BACKLOG.md.

## Where things live

| What | Where |
|---|---|
| App registrations, scopes, roles, test users, consent | `infra/identity` (Terraform, `azuread` provider) |
| Token validation + role policies | `src/<Service>/Auth/AuthSetup.cs`, policies per route in `Endpoints/` |
| On-Behalf-Of | `src/ApplicationService/Program.cs` (typed clients), `appsettings.json` (`DownstreamApis`) |
| Public IDs (tenant, client IDs) | `src/<Service>/appsettings.json` (`AzureAd`), `src/WebApp/.env` |
| Sign-in UI | `src/WebApp/src/auth/`, `App.tsx`; role-based UI in the pages |
| ApplicationService's managed identity (Azure) | `infra/terraform/main.tf`, env vars in `apps.tf` |
| Authorization tests | `tests/<Service>.Tests/Auth/` (real policies, fake sign-in) |

## Setup (once) — you run these

Requires: signed in to the Azure CLI as an administrator of the tenant
(`az login --tenant bc007f10-f168-4358-87be-cc46d95c87ef`).

**1. Terraform state storage.** `infra/identity` keeps its state next to the platform's,
in `ats-tfstate-rg`. If that resource group doesn't exist (e.g. after a full teardown):

```powershell
az group create -n ats-tfstate-rg -l centralindia
az storage account create -n atstfstate4sqlo -g ats-tfstate-rg -l centralindia --sku Standard_LRS --min-tls-version TLS1_2 --allow-blob-public-access false
az storage container create -n tfstate --account-name atstfstate4sqlo
```

**2. Create the Entra side** — app registrations, scopes, roles, consent, two test
users, role assignments (you get Recruiter too):

```powershell
terraform -chdir=infra/identity init
terraform -chdir=infra/identity plan    # ~50 resources; nothing in Azure subscriptions, only Entra
terraform -chdir=infra/identity apply
```

**3. Fill in the public IDs** (not secrets — they're committed):

```powershell
terraform -chdir=infra/identity output -raw webapp_env   # -> src/WebApp/.env
terraform -chdir=infra/identity output api_client_ids    # -> AzureAd:ClientId in each service's appsettings.json
terraform -chdir=infra/identity output api_scopes        # -> DownstreamApis:*:Scopes in ApplicationService's appsettings.json
```

**4. The secret** (ApplicationService's local On-Behalf-Of credential — never commit it):

```powershell
terraform -chdir=infra/identity output -raw application_api_client_secret
# docker compose: put it in a root .env file (template: .env.example)
# dotnet run:     dotnet user-secrets set "AzureAd:ClientCredentials:0:ClientSecret" "<secret>" --project src/ApplicationService
```

**5. Test users:**

```powershell
terraform -chdir=infra/identity output -json test_users   # UPNs and passwords
```

`ats-recruiter@…` is a Recruiter, `ats-hiringmanager@…` a HiringManager. On first
sign-in the tenant's security defaults ask them to set up MFA (Microsoft
Authenticator) — expected.

## Running locally

Same as before (README), plus sign-in: `docker compose up --build` →
http://localhost:5100, or `npm run dev` → http://localhost:5173. Sign in as a test
user and compare what each role sees. The services need internet access to fetch
Entra's signing keys.

Calling an API directly (curl / `.http` files) needs a token for **that** API. The
Azure CLI is pre-authorized for the APIs, so for a user with a role:

```powershell
az account get-access-token --scope api://<client-id>/access_as_user --query accessToken -o tsv
```

## In Azure

After this is merged, the infra pipeline creates ApplicationService's managed
identity (`id-ats-application-…`). Then, once:

```powershell
terraform -chdir=infra/terraform output -raw application_identity_principal_id
terraform -chdir=infra/identity apply -var "application_managed_identity_principal_id=<that id>"
```

That creates a **federated credential**: Entra trusts the managed identity to act
as the ATS Application API app, so On-Behalf-Of works in Azure with no secret.

## Troubleshooting

| Symptom | Likely cause |
|---|---|
| `AADSTS50105` at sign-in | The user has no role on ATS Web — assign one (`infra/identity` variables). |
| `AADSTS50011` redirect URI mismatch | The site's origin isn't in `spa_redirect_uris`. |
| Every API call 401 | `AzureAd:ClientId` in the service still the placeholder, or the web app's scope in `.env` points at a different API. |
| Submitting an application fails, ApplicationService logs `AADSTS7000215` / `MsalServiceException` | Missing or wrong client secret (step 4), or (Azure) the federated credential isn't created yet. |
| A user gets 403 they shouldn't | Role not assigned on **that** API — roles are per app; the identity stack assigns them on all four. |

## Security notes

- Client IDs and the tenant ID are public identifiers; committing them is fine.
- The local client secret and the test users' passwords live in the Terraform state
  (sensitive outputs, private storage account). Acceptable for a learning tenant;
  for real use, rotate the secret and keep it in Key Vault (BACKLOG.md).
- Azure CLI pre-authorization and the test users are dev conveniences — drop them for
  production.
