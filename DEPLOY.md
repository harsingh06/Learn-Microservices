# Deploying ATS to Azure Container Apps with Terraform

Every step is a command you run yourself — no scripts, no CI/CD (that comes later).
All commands run from the repo root unless noted. Estimated first deploy: ~20 minutes.

## The shape of the deployment

```
Resource group: ats-rg (Central India)
├── ats<suffix>acr           Azure Container Registry (Basic) — your 4 images
├── ats-logs                 Log Analytics — container logs land here
├── ats-apps-identity        managed identity the apps use to pull from ACR
├── ats-env                  Container Apps environment (shared network + domain)
│   ├── ats-candidate        candidate-service  :8080 → public https URL
│   ├── ats-job              job-service        :8080 → public https URL
│   ├── ats-application      application-service:8080 → public https URL
│   └── ats-webapp           nginx + React      :80   → public https URL
└── ats-<suffix>-cosmos      Cosmos DB (free tier) — candidates-db / jobs-db / applications-db
```

Same topology as `docker-compose.yml`, with Azure services substituting for the
emulator and the compose network. The services themselves are unchanged — only
`Cosmos__Endpoint`/`Cosmos__Key` and `Services__*` env vars differ.

## Why the deploy is two `terraform apply` passes

A container app can't be created until its image exists in ACR — and ACR itself
is created by Terraform. So:

1. **Apply #1** (`deploy_apps = false`) creates everything *except* the apps
   (registry, environment, Cosmos, identity).
2. Build and push the four images.
3. **Apply #2** (`deploy_apps = true`) creates the four apps.

This is a real microservices lesson: infrastructure lifecycle ≠ image lifecycle.
(The webapp image needs no environment-specific build args: nginx reverse-proxies
`/api/*` to URLs supplied at runtime via env vars, set by Terraform.)

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
terraform output   # note acr_name and the four *_url values
```

> Free-tier note: only one free-tier Cosmos account is allowed per subscription.
> If `apply` fails with a free-tier error, set `free_tier_enabled = false` in
> `cosmos.tf` (costs a bit more) or delete the other free-tier account.

## 3. Build and push the four images

`az acr build` uploads the source and builds **in Azure** — local Docker not needed.
Replace `<acr_name>` and the URLs with your `terraform output` values.

```powershell
cd ../..    # back to repo root

az acr build -r <acr_name> -t candidate-service:v1   src/CandidateService
az acr build -r <acr_name> -t job-service:v1         src/JobService
az acr build -r <acr_name> -t application-service:v1 src/ApplicationService

az acr build -r <acr_name> -t webapp:v1 src/WebApp
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
> docker build -t <acr_login_server>/webapp:v1 src/WebApp
> docker push <acr_login_server>/candidate-service:v1
> docker push <acr_login_server>/job-service:v1
> docker push <acr_login_server>/application-service:v1
> docker push <acr_login_server>/webapp:v1
> ```

## 4. Apply #2 — create the container apps

Edit `infra/terraform/terraform.tfvars`: set `deploy_apps = true`. Then:

```powershell
cd infra/terraform
terraform plan     # exactly 4 new resources: the container apps
terraform apply
```

## 5. Verify

```powershell
curl https://<candidate_api_url>/health      # {"status":"ok",...} x3 services
curl https://<job_api_url>/health
curl https://<application_api_url>/health
```

First request after idle is slow (~10-20 s): `min_replicas = 0` means apps scale
to zero and cold-start on demand. That's the cost/latency trade-off — set
`min_replicas = 1` in `terraform.tfvars` if it annoys you.

Then open `webapp_url` in a browser and click through: create a candidate, a job,
apply, change the application status. Check the documents in the portal:
Cosmos account → Data Explorer → each service's own database.

Logs: portal → Container App → **Log stream** (live), or Logs (Log Analytics):

```kusto
ContainerAppConsoleLogs_CL | where ContainerAppName_s == "ats-application" | take 50
```

## 6. Shipping a code change

Images are immutable; roll forward by tag:

```powershell
az acr build -r <acr_name> -t candidate-service:v2 src/CandidateService
# set image_tag = "v2" in terraform.tfvars, then:
terraform apply    # updates the apps' template → new revision rolls out
```

(One tag for all four apps keeps it simple; per-service tags are a later refinement.)

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
| `azurerm_container_app_environment.main` | Container Apps Environments → ats-env |
| `azurerm_container_app.*` | Container Apps → each app → Revisions, Log stream, Ingress |
| `azurerm_cosmosdb_account.main` | Azure Cosmos DB → Data Explorer |
| `azurerm_container_registry.main` | Container registries → Repositories (your 4 images) |
| `azurerm_role_assignment.acr_pull` | Container registry → Access control (IAM) |
| `azurerm_log_analytics_workspace.main` | Log Analytics workspaces → Logs |
