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
- [x] **CI/CD** (GitHub Actions): per-service pipelines (build → test → image → ACA)
      + infra pipeline (terraform plan on PR, apply on main). OIDC auth, no stored
      credentials. Follow-ups:
  - [ ] Post the terraform plan as a PR comment instead of reading job logs.
  - [ ] GitHub environment protection rule (manual approval gate) before apply/deploy.
- [ ] **AKS** as the second deployment target (compare against ACA).

## Phase 5 — Production hardening

- [ ] Resiliency on sync calls (timeouts, retries, circuit breaker via `Microsoft.Extensions.Http.Resilience`).
- [ ] Idempotent event consumers (at-least-once delivery means duplicates).
- [ ] Observability: OpenTelemetry traces across service boundaries, health checks wired
      into orchestrator probes.
- [ ] Redis cache if (and only if) a real read-hotspot appears.
