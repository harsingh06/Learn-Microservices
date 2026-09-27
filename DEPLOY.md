# Deploying ATS to Azure Container Apps with Terraform

Every step is a command you run yourself — no scripts, no CI/CD (that comes later).
All commands run from the repo root unless noted. Estimated first deploy: ~20 minutes.

## The shape of the deployment

```
Resource group: rg-ats-prod-cin-01 (Central India)
├── acratsprodcin01                Azure Container Registry (Basic) — your 4 images
├── log-ats-prod-cin-01            Log Analytics — container logs land here
├── id-ats-apps-prod-cin-01        managed identity the apps use to pull from ACR
├── cae-ats-prod-cin-01            Container Apps environment (shared network + domain)
│   ├── rtatsprodcin01             rule-based routing (PREVIEW) → THE public entry point:
│   │                                /api/<resource>/* → services, / → webapp (+ custom domain)
│   ├── ca-ats-candidate-prod-cin-01    candidate-service  :8080 → internal-only
│   ├── ca-ats-job-prod-cin-01          job-service        :8080 → internal-only
│   ├── ca-ats-application-prod-cin-01  application-service:8080 → internal-only
│   └── ca-ats-webapp-prod-cin-01       nginx + React      :80   → internal-only
└── cosmos-ats-prod-cin-01         Cosmos DB (free tier) — candidates-db / jobs-db / applications-db
```

### Naming convention

`<type>-<workload>-<environment>-<region>-<instance>` — type abbreviations from
Microsoft's Cloud Adoption Framework (`rg`, `log`, `acr`, `id`, `cae`, `ca`,
`cosmos`), region `cin` = Central India, instance `01` (a second copy of the same
environment side by side would be `02`). ACR and the route config forbid hyphens,
so they use the same parts run together. Every name is built in one place: the
`locals` block at the top of `infra/terraform/main.tf`. Every resource is tagged
`workload`, `environment`, `managed-by=terraform`.

No VNet: the environment uses Azure-managed networking, and Cosmos accepts
public network traffic authenticated by its account key.

Same topology as `docker-compose.yml`, with Azure services substituting for the
emulator and the compose network. The services themselves are unchanged — only
`Cosmos__Endpoint`/`Cosmos__Key` and `Services__*` env vars differ.

## Why the deploy is two `terraform apply` passes

A container app can't be created before its image exists in ACR, so:

1. **Apply #1** (`deploy_apps = false`) creates everything *except* the apps and
   outputs the future URLs (`route_url`, the route-config FQDN, is the site).
2. `az acr build` builds the images in the cloud. The webapp needs no URL: it
   shares an origin with the APIs and calls relative `/api/...` paths.
3. **Apply #2** (`deploy_apps = true`) creates the four apps + the route config
   (an `httpRouteConfigs` PREVIEW resource, managed via the azapi provider —
   if apply fails with an unknown-resource-type error, the preview may not be
   available in your region yet).

This is a real microservices lesson: infrastructure lifecycle ≠ image lifecycle.

## 0. Prerequisites (once)

```powershell
winget install HashiCorp.Terraform     # then open a NEW terminal
terraform -version                     # expect >= 1.9

az login                               # browser sign-in
az account show --query name -o tsv    # confirm the right subscription
```

## 1. Initialize Terraform

```powershell
cd infra/terraform
terraform init          # downloads the azurerm + random providers
terraform fmt -check    # style check (should be silent)
terraform validate      # config sanity check
```

Create `terraform.tfvars` (git-ignored) from the example:

```powershell
Copy-Item terraform.tfvars.example terraform.tfvars
az account show --query id -o tsv    # paste this as subscription_id in terraform.tfvars
```

Register the resource providers this stack uses (once per subscription; Terraform's
azurerm v4 does not auto-register them, so a fresh subscription 409s with
`MissingSubscriptionRegistration` otherwise). Use the same subscription as tfvars:

```powershell
az provider register --namespace Microsoft.App --subscription <subscription_id> --wait
az provider register --namespace Microsoft.DocumentDB --subscription <subscription_id> --wait
az provider register --namespace Microsoft.OperationalInsights --subscription <subscription_id> --wait
az provider register --namespace Microsoft.ContainerRegistry --subscription <subscription_id> --wait
az provider register --namespace Microsoft.ManagedIdentity --subscription <subscription_id> --wait
```

## 2. Apply #1 — infrastructure (no apps yet)

```powershell
terraform plan     # read it! ~13 resources, no container apps
terraform apply    # type: yes  (~5-8 min; Cosmos is the slow one)
terraform output   # note acr_name and route_url
```

> Free-tier note: only one free-tier Cosmos account is allowed per subscription.
> If `apply` fails with a free-tier error, set `free_tier_enabled = false` in
> `cosmos.tf` (costs a bit more) or delete the other free-tier account.

## 3. Build and push the four images

`az acr build` uploads the source and builds **in Azure** — local Docker not needed.
Replace `<acr_name>` with your `terraform output` value.

```powershell
cd ../..    # back to repo root

az acr build -r <acr_name> -t candidate-service:v1   src/CandidateService
az acr build -r <acr_name> -t job-service:v1         src/JobService
az acr build -r <acr_name> -t application-service:v1 src/ApplicationService

# Empty VITE_API_URL = relative /api calls (same origin as the site)
az acr build -r <acr_name> -t webapp:v1 `
  --build-arg VITE_API_URL= `
  src/WebApp
```

> **`TasksOperationsNotAllowed`?** Microsoft blocks ACR Tasks on free-trial,
> student, and some new subscriptions (anti-abuse). Either file the free support
> ticket the error links, or — simpler — build locally and push (identical
> result; Docker Desktop must be running):
>
> ```powershell
> az acr login --name <acr_name>
> docker build -t <acr_login_server>/candidate-service:v1 src/CandidateService
> docker build -t <acr_login_server>/job-service:v1 src/JobService
> docker build -t <acr_login_server>/application-service:v1 src/ApplicationService
> docker build -t <acr_login_server>/webapp:v1 `
>   --build-arg VITE_API_URL= `
>   src/WebApp
> docker push <acr_login_server>/candidate-service:v1
> docker push <acr_login_server>/job-service:v1
> docker push <acr_login_server>/application-service:v1
> docker push <acr_login_server>/webapp:v1
> ```

## 4. Apply #2 — create the container apps

Edit `infra/terraform/terraform.tfvars`: set `deploy_apps = true`. Then:

```powershell
cd infra/terraform
terraform plan     # the 4 container apps + the route config
terraform apply
```

## 5. Verify

Everything goes through the one entry point (`route_url`, or `site_url` once a
custom domain is set):

```powershell
curl <route_url>/                      # the webapp's index.html
curl <route_url>/api/candidates        # [] or your candidates
curl <route_url>/api/jobs
curl <route_url>/api/applications
```

First request after idle is slow (~10-20 s): `min_replicas = 0` means apps scale
to zero and cold-start on demand. That's the cost/latency trade-off — set
`min_replicas = 1` in `terraform.tfvars` if it annoys you.

Then open the same URL in a browser and click through: create a candidate, a job,
apply, change the application status. Check the documents in the portal:
Cosmos account → Data Explorer → each service's own database.

Logs: portal → Container App → **Log stream** (live), or Logs (Log Analytics):

```kusto
ContainerAppConsoleLogs_CL | where ContainerAppName_s == "ca-ats-application-prod-cin-01" | take 50
```

## 6. Shipping a code change

Push to `main` and the service's pipeline builds `<service>:<git sha>` and rolls
it out with `az containerapp update`. To redeploy without a code change (e.g.
after the environment is recreated), run the workflow manually:
`gh workflow run candidate-service.yml` (likewise job/application/webapp).

`image_tag` in Terraform is only the **initial** image when an app is first
created — the apps `ignore_changes` on the image, so bumping it later does nothing.

## Custom domain for the site (optional)

The domain is bound to the **route config**, not the webapp, so one hostname
serves both the webapp (`/`) and the APIs (`/api/...`) — same origin, no CORS.
A domain can be bound to only ONE of: an app, a route config, or the environment.
Order matters: Azure validates domain ownership when the hostname is added, so
DNS must exist first.

**1. Create two records at your DNS provider/registrar:**

| Type | Name | Value |
|---|---|---|
| TXT | `asuid.<sub>` (e.g. `asuid.ats`) | the environment's verification id: `az containerapp env show -n cae-ats-prod-cin-01 -g rg-ats-prod-cin-01 --query properties.customDomainConfiguration.customDomainVerificationId -o tsv` |
| CNAME | `<sub>` (e.g. `ats`) | the route config FQDN (`terraform output route_url`, without `https://`) |

(An apex domain can't be a CNAME — use an A record to the environment's static IP,
`az containerapp env show -n cae-ats-prod-cin-01 -g rg-ats-prod-cin-01 --query properties.staticIp -o tsv`.)
Wait until both resolve (`Resolve-DnsName asuid.<sub>.<domain> -Type TXT`).

**2. Add the hostname via Terraform** — set the domain and apply:

- Pipeline path: set the repo variable, then re-run infra (or push an infra change):
  `gh variable set WEBAPP_CUSTOM_DOMAIN --body "ats.harsingh.com"`
- Local path: add `webapp_custom_domain = "ats.harsingh.com"` to `terraform.tfvars`
  and `terraform apply`.

The route config lists it with `bindingType = "Auto"`: HTTP-only until a managed
certificate for that hostname exists in the environment, then attached automatically.

**3. Create the free managed certificate** (one-time per environment; neither
azurerm nor our Terraform creates it):

```powershell
az containerapp env certificate create -g rg-ats-prod-cin-01 -n cae-ats-prod-cin-01 `
  --hostname ats.harsingh.com --validation-method CNAME `
  --certificate-name cert-ats-prod-cin-01
```

Issuance takes a few minutes; afterwards `https://ats.harsingh.com` serves the
site. The route config's default FQDN keeps working alongside it.

## 7. Tear down (stop all billing)

```powershell
cd infra/terraform
terraform destroy    # type: yes — deletes the whole resource group's contents
```

Destroying also frees your subscription's single Cosmos free-tier slot.

## What this costs while deployed (approx.)

| Resource | Cost |
|---|---|
| Cosmos 3×400 RU/s | free tier covers 1000 RU/s → ~200 RU/s billed ≈ **$12/mo** |
| Container Apps ×4 | consumption plan + scale-to-zero → pennies at learning traffic |
| ACR Basic | ~**$5/mo** |
| Log Analytics | negligible at this volume |

`terraform destroy` after each session keeps a month well under a few dollars.

## Terraform ↔ portal map (learning aid)

| Terraform resource | Where to look in the portal |
|---|---|
| `azurerm_container_app_environment.main` | Container Apps Environments → cae-ats-prod-cin-01 |
| `azurerm_container_app.*` | Container Apps → each app → Revisions, Log stream, Ingress |
| `azurerm_cosmosdb_account.main` | Azure Cosmos DB → Data Explorer |
| `azurerm_container_registry.main` | Container registries → Repositories (your 4 images) |
| `azurerm_role_assignment.acr_pull` | Container registry → Access control (IAM) |
| `azurerm_log_analytics_workspace.main` | Log Analytics workspaces → Logs |
