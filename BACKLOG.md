# Backlog

Deliberately deferred work, roughly in the order it makes sense to tackle it.
Each item notes *why* it was deferred so we remember the trade-off we accepted.

## Phase 2 — Asynchronous messaging (removed from Phase 1 scope)

- [ ] **Azure Service Bus integration.** One topic (`ats-events`), one subscription per
      consumer, event type in the message `Subject`. Locally, use Microsoft's Service Bus
      emulator in docker-compose (needs a companion SQL Edge container).
- [ ] **Publish domain events** from each service after a successful save:
      `CandidateCreated`, `JobCreated`, `ApplicationSubmitted`, `ApplicationStatusChanged`.
      Keep an `IEventPublisher` abstraction per service; duplicate the small event records
      per service instead of sharing a contracts DLL (independent deployability).
- [ ] **NotificationWorker** (.NET Worker Service, `src/NotificationWorker/`): consume
      events and log "would send email…" — no real email yet.
- [ ] **Transactional outbox pattern.** Save-then-publish is a dual write: a crash between
      the Cosmos save and the Service Bus publish silently loses the event. Fine while
      events only drive log-only notifications; must be fixed before anything
      business-critical consumes them.

## Phase 3 — Decoupling improvements

- [ ] **Replace sync existence checks in ApplicationService** with an event-fed local read
      model of candidates/jobs (event-carried state transfer). Removes the availability
      coupling: today, if CandidateService is down you cannot apply to a job.
- [ ] **Refresh denormalized snapshots.** `candidateName`/`jobTitle` on an application go
      stale if the source is renamed; consume `CandidateUpdated`/`JobUpdated` to fix.
- [ ] **Event contract versioning** (shared schema validation or versioned packages) once
      more than one consumer exists and drift becomes a real risk.

## Phase 4 — Edge and platform

- [x] **API routing / gateway** — settled on **ACA rule-based routing** (env-level
      `httpRouteConfigs`, PREVIEW, via azapi in Terraform): one public API FQDN,
      `/api/<resource>/*` → owning app, API apps internal-only. History: an
      nginx-proxy-inside-the-webapp was rejected (mixed responsibilities), a
      standalone YARP gateway was built and then replaced by the platform feature
      (nothing of ours to run; trade-off: no self-owned edge for cross-cutting
      concerns). Locally, `local/dev-router` (compose) and Vite's proxy stand in.
      Follow-ups:
  - [ ] The preview risk: track rule-based routing to GA; revisit if limits bite.
  - [ ] Tighten each service's CORS to the webapp origins instead of
        AllowAnyOrigin (CORS must stay on services — the routing layer adds none).
  - [ ] Custom domain (e.g. api.harsingh.com) on the route config.
  - [ ] When auth/rate-limiting arrive: Azure API Management in front, or
        resurrect the YARP gateway (git history has it: commit `0681f7a`).
- [ ] **Authentication/authorization** (Entra ID) — after the gateway exists.
- [x] **Deployment to Azure Container Apps via Terraform** — done, see `infra/terraform/`
      and `DEPLOY.md`. Follow-ups now unlocked:
  - [x] Remote Terraform state (Azure Storage backend `ats-tfstate-rg`).
  - [x] Per-service image tags — pipelines deploy `<service>:<git sha>`.
  - [ ] Cosmos data-plane auth via managed identity instead of the account key
        (code change: `CosmosClient` with `DefaultAzureCredential`).
  - [x] VNet: ACA environment in `snet-aca`, Cosmos reachable only via a private
        endpoint in `snet-pe` (public network access disabled). Trade-off: portal
        Data Explorer no longer works from outside the VNet; ~$8/mo.
    - [ ] NSGs on the subnets (defence in depth; nothing needs them yet).
    - [ ] ACR private endpoint — requires the Premium SKU (~$50/mo), deferred for cost.
    - [ ] **Self-hosted runners inside the VNet** — ACA Jobs as GitHub runners, scaled
          from the workflow job queue by KEDA's `github-runner` scaler (scale to zero).
          Prerequisite for making any *data plane* the pipelines touch private: ACR
          (`docker push`), the tfstate storage account (`terraform init`), a future
          Key Vault, or smoke tests against an internal-only environment.
          Deploys themselves (`terraform apply`, `az containerapp update`) go through
          the public ARM control plane and never need this. Deferred: today only
          Cosmos is private and no pipeline step touches its data plane (hybrid
          model). Alternative: GitHub-hosted runners with Azure private networking
          (needs a GitHub Team/Enterprise plan).
- [x] **CI/CD** (GitHub Actions): per-service pipelines (build → test → image → ACA)
      + infra pipeline (terraform plan on PR, apply on main). OIDC auth, no stored
      credentials.
- [x] **Pipeline hardening**: format/lint gates, coverage reporting, CodeQL,
      Dependabot, Trivy (container images pre-push + Terraform config), terraform
      plan posted as a sticky PR comment, and branch protection on `main`
      (PR required; CodeQL checks required). Follow-ups:
  - [x] Post the terraform plan as a PR comment instead of reading job logs.
  - [ ] Post-deploy smoke test: curl the deployed endpoint after
        `az containerapp update` so the pipeline proves the deploy, not just
        that the command exited 0.
  - [ ] Speed/hygiene: NuGet caching, `concurrency:` to cancel superseded runs.
  - [ ] Fix the 3 pre-existing oxlint `set-state-in-effect` warnings, then
        consider `--deny-warnings`.
  - [x] Triaged Trivy IaC findings (53 checks apply, all passing) and raised
        IaC enforcement to HIGH+CRITICAL. If it stays clean, MEDIUM is the
        next notch — 27 MEDIUM checks currently pass.
  - [ ] GitHub environment protection rule (manual approval gate) before apply/deploy.
  - [ ] Required approvals > 0 on the branch protection rule if anyone else joins.
- [ ] **AKS** as the second deployment target (compare against ACA).

## Phase 5 — Production hardening

- [ ] Resiliency on sync calls (timeouts, retries, circuit breaker via `Microsoft.Extensions.Http.Resilience`).
- [ ] Idempotent event consumers (at-least-once delivery means duplicates).
- [ ] Observability: OpenTelemetry traces across service boundaries, health checks wired
      into orchestrator probes.
- [ ] Redis cache if (and only if) a real read-hotspot appears.

## Low priority — someday

- [ ] **Split into separate repos** (platform/infra repo + one repo per service).
      Do it in two steps, the boundary first:
  1. In this repo: split Terraform into `infra/platform` (RG, VNet, ACA environment,
     ACR, Log Analytics, Cosmos *account* + private endpoint, route config) and a
     per-service stack (its container app, its Cosmos *database*), each with its own
     state; add `CODEOWNERS`. Pairs naturally with multi-env.
  2. Only then extract folders with `git filter-repo` (keeps history) and move
     `service-pipeline.yml` to a shared repo as a versioned reusable workflow.
  Deferred: one person owns everything, and per-service pipelines already give
  independent deploys. Costs of splitting: coordinated multi-repo PRs for
  cross-cutting changes, per-repo OIDC credentials/secrets/branch protection/
  Dependabot, a new home for local-dev compose, and API contracts become mandatory.
  Open questions: does a service own its container app definition or only its image?
  Who owns the shared route config?
