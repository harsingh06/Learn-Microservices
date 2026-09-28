# Deploying ATS to Azure Container Apps with Terraform

All commands run from the repo root unless noted. Day to day, the GitHub Actions
pipelines do all of this; this guide is for standing up a brand-new environment by
hand and for understanding what the pipelines do.

## The shape of the deployment

Three layers, each with its own Terraform state and its own pipeline:

| Layer | Where | Owns | Applied by |
|---|---|---|---|
| **Platform** | `infra/platform` | everything shared or stateful: RG, ACR, logs, identity, Container Apps environment, **Cosmos account + every database**, **route config**, **Front Door** | `infra.yml` |
| **Module** | `infra/modules/container-app-service` | the standard for one app (internal-only ingress, identity, registry, profile) — compute only | nobody directly (a library) |
| **Service** | `src/<Service>/infra` | its own container app: image, env vars, scaling | that service's pipeline |

```
User ──► Front Door afd-ats-prod-cin-01  (ats.harsingh.com, managed TLS, WAF, /assets cache)
           └── origin: route config rtatsprodcin01  (/api/<resource>/* → services, / → webapp)

Resource group: rg-ats-prod-cin-01 (Central India)
├── acratsprodcin01                Azure Container Registry (Basic) — your 4 images
├── log-ats-prod-cin-01            Log Analytics — container logs land here
├── id-ats-apps-prod-cin-01        managed identity the apps use to pull from ACR
├── afd-ats-prod-cin-01            Front Door (Standard) + endpoint fde-ats-prod-cin-01
├── fdfpatsprodcin01               Front Door WAF policy (rate limit on /api)
├── cae-ats-prod-cin-01            Container Apps environment
│   ├── rtatsprodcin01             rule-based routing (PREVIEW) — Front Door's origin
│   ├── ca-ats-candidate-prod-cin-01    candidate-service  :8080 → internal-only   ┐
│   ├── ca-ats-job-prod-cin-01          job-service        :8080 → internal-only   │ service
│   ├── ca-ats-application-prod-cin-01  application-service:8080 → internal-only   │ stacks
│   └── ca-ats-webapp-prod-cin-01       nginx + React      :80   → internal-only   ┘
└── cosmos-ats-prod-cin-01         Cosmos DB (free tier) — candidates-db / jobs-db / applications-db
```

Service stacks read what they need from the platform through its **outputs**
(`container_app_platform`, `app_names`, `internal_urls`, `cosmos_*` — see
`infra/platform/outputs.tf`). Those outputs are a contract: renaming one breaks
every service.

### Naming convention

`<type>-<workload>-<environment>-<region>-<instance>` — type abbreviations from
Microsoft's Cloud Adoption Framework (`rg`, `log`, `acr`, `id`, `cae`, `ca`,
`cosmos`, `afd`, `fde`, `fdfp`), region `cin` = Central India, instance `01` (a
second copy of the same environment side by side would be `02`). ACR, the route
config and the WAF policy forbid hyphens, so they use the same parts run together.
Every name is built in one place: the `locals` block at the top of
`infra/platform/main.tf` — the service stacks take their app name from the
platform's `app_names` output. Every resource is tagged `workload`,
`environment`, `managed-by=terraform`.

No VNet: the environment uses Azure-managed networking, and Cosmos accepts
public network traffic authenticated by its account key.

Same topology as `docker-compose.yml`, with Azure services substituting for the
emulator and the compose network. The services themselves are unchanged — only
`Cosmos__Endpoint`/`Cosmos__Key` and `Services__*` env vars differ.

## Why a new environment is platform → services → platform

1. The **platform** apply creates the environment, registry, Cosmos and Front
   Door. It can't create the route config's rules yet: Azure rejects a rule whose
   target app doesn't exist (`terraform output pending_routes` lists them).
2. Each **service pipeline** builds and pushes its image, then applies its own
   stack — which creates its container app with that image. No placeholder
   image, no `v1`, no "create the apps later" switch.
3. The **platform** apply again: the apps exist now, so the route rules are
   created and the site comes up.

After that, day-to-day changes are a single pipeline each.

## 0. Prerequisites (once)

```powershell
winget install HashiCorp.Terraform     # then open a NEW terminal
terraform -version                     # expect >= 1.9

az login                               # browser sign-in
az account show --query name -o tsv    # confirm the right subscription
```

Register the resource providers the stacks use (once per subscription; Terraform's
azurerm v4 does not auto-register them, so a fresh subscription 409s with
`MissingSubscriptionRegistration` otherwise):

```powershell
az provider register --namespace Microsoft.App --subscription <subscription_id> --wait
az provider register --namespace Microsoft.DocumentDB --subscription <subscription_id> --wait
az provider register --namespace Microsoft.OperationalInsights --subscription <subscription_id> --wait
az provider register --namespace Microsoft.ContainerRegistry --subscription <subscription_id> --wait
az provider register --namespace Microsoft.ManagedIdentity --subscription <subscription_id> --wait
az provider register --namespace Microsoft.Cdn --subscription <subscription_id> --wait   # Front Door
```

## 1. Platform — first apply

```powershell
cd infra/platform
Copy-Item terraform.tfvars.example terraform.tfvars   # git-ignored; fill in subscription_id
terraform init
terraform plan     # read it! RG, ACR, logs, identity, environment, Cosmos, Front Door
terraform apply    # type: yes  (~5-8 min; Cosmos is the slow one)
terraform output   # note acr_name, acr_login_server, pending_routes (all four apps)
```

> Free-tier note: only one free-tier Cosmos account is allowed per subscription.
> If `apply` fails with a free-tier error, set `free_tier_enabled = false` in
> `cosmos.tf` (costs a bit more) or delete the other free-tier account.

## 2. Services — each creates its own app

The pipelines need the registry's name:

```powershell
gh variable set ACR_NAME --body "<acr_name>"
gh variable set ACR_LOGIN_SERVER --body "<acr_login_server>"
```

Then run each service pipeline (build → test → scan → push → `terraform apply`
of `src/<Service>/infra`):

```powershell
gh workflow run candidate-service.yml
gh workflow run job-service.yml
gh workflow run application-service.yml
gh workflow run webapp.yml
```

> **First environment after the migration?** Each `src/<Service>/infra` holds a
> one-time `imports.tf` (adopting apps the platform used to manage) — delete
> them first: on a brand-new environment there is nothing to import.

By hand instead (Docker Desktop running), per service:

```powershell
az acr login --name <acr_name>
docker build -t <acr_login_server>/candidate-service:manual1 src/CandidateService
docker push <acr_login_server>/candidate-service:manual1
cd src/CandidateService/infra
terraform init
terraform apply -var subscription_id=<subscription_id> -var image=<acr_login_server>/candidate-service:manual1
```

(The webapp builds with `--build-arg VITE_API_URL=` — empty, so it calls
relative `/api` paths on its own origin.)

## 3. Platform — second apply (routes)

```powershell
cd infra/platform
terraform apply    # creates the route config; pending_routes is now []
```

## 4. Verify

Everything goes through Front Door (`site_url`); `route_url` is the origin behind it:

```powershell
curl <site_url>/                      # the webapp's index.html
curl <site_url>/api/candidates        # [] or your candidates
curl <site_url>/api/jobs
curl <site_url>/api/applications
```

First request after idle is slow (~10-20 s): the apps scale to zero
(`min_replicas = 0`, the module default) and cold-start on demand. A service can
override it in its `src/<Service>/infra/main.tf`.

Then open the site in a browser and click through: create a candidate, a job,
apply, change the application status. Check the documents in the portal:
Cosmos account → Data Explorer → each service's own database.

Logs: portal → Container App → **Log stream** (live), or Logs (Log Analytics):

```kusto
ContainerAppConsoleLogs_CL | where ContainerAppName_s == "ca-ats-application-prod-cin-01" | take 50
```

## 5. Day to day

| Change | Where | What runs |
|---|---|---|
| Service code | `src/<Service>/**` | that service's pipeline → new image → `terraform apply` of its stack |
| A service's scaling, env vars | `src/<Service>/infra` | the same service pipeline |
| The app standard (ingress, identity, …) | `infra/modules/container-app-service` | **all four** service pipelines |
| Shared/stateful infra, routes, Front Door | `infra/platform` | `infra.yml` |

Each app has exactly one writer — its own service stack — so an infra apply
can no longer revert a concurrent image deploy. Redeploy without a code change:
`gh workflow run candidate-service.yml` (likewise job/application/webapp).

**Adding a service:** create its folder with `infra/` (copy a sibling's stack),
add a workflow, deploy it — then a platform PR adds its component to
`app_names` (main.tf), its database (cosmos.tf) and its route rule (routing.tf).
Exposure and data stay platform decisions.

## Custom domain on Front Door

Front Door holds the domain and its free managed certificate, all in Terraform —
one hostname serves the webapp (`/`) and the APIs (`/api/...`): same origin, no CORS.

**1. Set the domain** — the platform then creates it on Front Door:

- Pipeline: `gh variable set WEBAPP_CUSTOM_DOMAIN --body "ats.harsingh.com"`, then
  re-run `infra.yml`.
- Local: `custom_domain = "ats.harsingh.com"` in `terraform.tfvars`, `terraform apply`.

**2. Create two records at your DNS provider** (values from `terraform output`):

| Type | Name | Value |
|---|---|---|
| TXT | `_dnsauth.<sub>` (e.g. `_dnsauth.ats`) | `custom_domain_validation.value` — proves you own the domain |
| CNAME | `<sub>` (e.g. `ats`) | `frontdoor_hostname` (`fde-ats-prod-cin-01-….azurefd.net`) |

Front Door validates the TXT record and issues the certificate on its own
(minutes, occasionally a few hours), and renews it automatically. Check:

```powershell
az afd custom-domain show -g rg-ats-prod-cin-01 --profile-name afd-ats-prod-cin-01 `
  --custom-domain-name ats-harsingh-com --query "{validation:domainValidationState,tls:tlsSettings.certificateType}"
```

An apex domain (`harsingh.com` itself) can't be a CNAME; it needs a DNS provider
with ALIAS/ANAME records (e.g. Azure DNS).

**What Front Door adds:** `/assets/*` (Vite's content-hashed files) is cached at
the edge; everything else is forwarded uncached. The WAF blocks a client IP
making more than 300 `/api` calls a minute. Known gap on the Standard tier: the
route config's own FQDN (`route_url`) is still publicly reachable, bypassing the
WAF — see BACKLOG.md.

## 6. Tear down (stop all billing)

Order matters: the service stacks first. The platform can't delete the resource
group while apps it doesn't manage are still in it (azurerm refuses to delete a
non-empty group).

```powershell
foreach ($svc in "CandidateService","JobService","ApplicationService","WebApp") {
  Push-Location src/$svc/infra
  terraform init
  terraform destroy -var subscription_id=<subscription_id> -var image=unused   # type: yes
  Pop-Location
}
cd infra/platform
terraform destroy    # type: yes — everything else
```

Destroying also frees your subscription's single Cosmos free-tier slot.

## What this costs while deployed (approx.)

| Resource | Cost |
|---|---|
| Cosmos 3×400 RU/s | free tier covers 1000 RU/s → ~200 RU/s billed ≈ **$12/mo** |
| Front Door Standard | ~**$35/mo** base + traffic (small at learning volume) |
| Front Door WAF policy | ~**$5/mo** + ~$1 per custom rule |
| Container Apps ×4 | consumption plan + scale-to-zero → pennies at learning traffic |
| ACR Basic | ~**$5/mo** |
| Log Analytics | negligible at this volume |

Front Door has no health probes configured (one origin): probes from every edge
location would keep the scale-to-zero apps awake around the clock.

## Terraform ↔ portal map (learning aid)

| Terraform resource | Where to look in the portal |
|---|---|
| `azurerm_container_app_environment.main` | Container Apps Environments → cae-ats-prod-cin-01 |
| `module.app.azurerm_container_app.this` (service stacks) | Container Apps → each app → Revisions, Log stream, Ingress |
| `azapi_resource.routes` | Container Apps Environment → HTTP route configs (preview) |
| `azurerm_cdn_frontdoor_*` | Front Door and CDN profiles → afd-ats-prod-cin-01 → Front Door manager, Domains |
| `azurerm_cdn_frontdoor_firewall_policy.main` | Web Application Firewall policies → fdfpatsprodcin01 |
| `azurerm_cosmosdb_account.main` | Azure Cosmos DB → Data Explorer |
| `azurerm_container_registry.main` | Container registries → Repositories (your 4 images) |
| `azurerm_role_assignment.acr_pull` | Container registry → Access control (IAM) |
| `azurerm_log_analytics_workspace.main` | Log Analytics workspaces → Logs |
