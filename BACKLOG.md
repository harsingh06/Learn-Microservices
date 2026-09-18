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

- [x] **BFF-lite reverse proxy.** The webapp's nginx (and Vite's dev proxy) forwards
      `/api/*` to the services — the browser talks to one origin. Follow-ups:
  - [ ] Flip the API container apps to internal-only ingress (verify ACA's
        `*.internal.` FQDN + TLS behavior for the proxy and app-to-app calls first).
  - [ ] Remove the now-unneeded permissive CORS policy from the three services.
  - [ ] A real gateway (YARP/APIM) when auth and cross-cutting concerns arrive.
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
