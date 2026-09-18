# ATS — Applicant Tracking System (microservices learning project)

A deliberately simple, production-*style* microservices application for hands-on learning
of microservices, Docker, and (later) Azure Container Apps, AKS, and DevOps.

## Architecture

```
 ┌─────────────────────┐          ┌───────────────────────────────┐
 │   React WebApp      │          │  API routing layer            │
 │   static files only │ Browser  │  Azure: ACA rule-based routes │
 │   :5100 / :5173 dev │ ───────► │  local: dev-router      :5104 │
 └─────────────────────┘  /api/*  │  /api/<resource>/* ────┬─┬─┬──┘
                                  └────────────────────────┼─┼─┼
        ┌───────────────────────────────────────────────── ┘ │ │
        ▼                       ┌─────────────────────────────┘ │
┌───────────────┐      ┌────────▼──────┐      ┌─────────────────▼───┐
│ Candidate     │      │ Job           │      │ Application         │
│ Service :5101 │◄─────┤ Service :5102 │◄─────┤ Service :5103       │
└───────┬───────┘ REST └───────┬───────┘ REST └──────────┬──────────┘
        │  (existence checks at apply time)              │
        ▼                      ▼                         ▼
  candidates-db            jobs-db               applications-db
        └──────────── Cosmos DB emulator :8081 ──────────┘
              (one emulator locally, one database per service)
```

| Service | Owns | Endpoints |
|---|---|---|
| **CandidateService** | Candidate profiles | `GET/POST /candidates`, `GET/PUT /candidates/{id}` (`?search=` on list) |
| **JobService** | Job postings | `GET/POST /jobs`, `GET/PUT /jobs/{id}` |
| **ApplicationService** | Candidate↔job applications + status workflow | `GET/POST /applications` (`?candidateId=&jobId=`), `GET /applications/{id}`, `PUT /applications/{id}/status` |

Status workflow (owned entirely by ApplicationService):
`Submitted → InReview → Accepted | Rejected` (Submitted can also go straight to Rejected).

Key decisions (and their trade-offs) are recorded in [BACKLOG.md](BACKLOG.md) — notably:
no messaging yet (Service Bus + NotificationWorker are Phase 2), and ApplicationService
validates candidate/job existence with synchronous REST calls and snapshots
`candidateName`/`jobTitle` into each application.

All browser API traffic goes to **one API origin** with `/api/<resource>/*` paths.
In Azure this is **ACA rule-based routing** (a preview, environment-level
`httpRouteConfig` managed via the azapi Terraform provider) — the platform routes
each prefix to the owning app and the API apps are **internal-only** (no public
FQDNs of their own). Locally the same role is played by a tiny nginx `dev-router`
container (compose) or Vite's dev proxy (`npm run dev`) — neither is ever deployed.
Trade-off vs. the earlier self-hosted YARP gateway: no app of ours to maintain,
but edge cross-cutting concerns (auth, rate limiting) will need APIM or a gateway
when they arrive; CORS therefore stays on each service.

## Prerequisites

- [.NET SDK 9.0](https://dotnet.microsoft.com/download/dotnet/9.0)
- [Node.js 22+](https://nodejs.org/)
- [Docker Desktop](https://www.docker.com/products/docker-desktop/)

## Option A — run everything with Docker Compose

```bash
docker compose up --build
```

First start takes a few minutes (image builds + Cosmos emulator boot; the services
retry until Cosmos is ready, so early connection warnings in the logs are normal).

| What | URL |
|---|---|
| Web UI | http://localhost:5100 |
| API origin (dev-router) | http://localhost:5104 (`/api/candidates`, `/api/jobs`, `/api/applications`) |
| Candidate API docs | http://localhost:5101/scalar/v1 |
| Job API docs | http://localhost:5102/scalar/v1 |
| Application API docs | http://localhost:5103/scalar/v1 |
| Cosmos Data Explorer | http://localhost:1234 |

Note: the Cosmos emulator (preview) does not persist data — restarting the `cosmos`
container starts you from an empty database.

## Option B — fast inner loop (emulator in Docker, code on the host)

Best for development: instant rebuilds and debugging.

```bash
# 1. Start only the Cosmos emulator
docker compose up cosmos

# 2. Run each service (three terminals) — ports are fixed in launchSettings.json
dotnet run --project src/CandidateService     # :5101
dotnet run --project src/JobService           # :5102
dotnet run --project src/ApplicationService   # :5103
# (no router needed here: Vite's dev proxy forwards /api/* — see vite.config.ts)

# 3. Run the UI
cd src/WebApp
npm install
npm run dev                                   # :5173
```

The `.http` files in each service folder (e.g. `src/CandidateService/CandidateService.http`)
contain ready-made requests you can send from VS Code (REST Client) or Rider/VS.

## Running the tests

```bash
dotnet test
```

Unit tests cover the endpoint handlers' business rules (validation, not-found,
duplicate applications, status transitions) against mocked repositories/clients —
no emulator or network needed.

## Project structure

```
src/
  CandidateService/      ASP.NET Core minimal API (.NET 9)
    Models/              Cosmos document + request DTOs
    Data/                ICandidateRepository + Cosmos implementation + startup init
    Endpoints/           HTTP handlers (static methods → directly unit-testable)
  JobService/            same layout
  ApplicationService/    same layout + Clients/ (typed HttpClients for sync checks)
  WebApp/                React 19 + TypeScript (Vite), four pages, no state library
local/dev-router/        nginx config: compose-only stand-in for ACA routing
tests/
  *.Tests/               xUnit + NSubstitute, one test project per service
docker-compose.yml       Cosmos emulator + 3 APIs + web UI
BACKLOG.md               deliberately deferred work (messaging, gateway, deployment, …)
```

Each service owns its data (its own Cosmos database), shares no code with the others,
and is built into its own container image — they are independently deployable.

## Configuration

Services read config from `appsettings.json`, overridable via environment variables
(see `docker-compose.yml` for examples):

| Setting | Meaning |
|---|---|
| `Cosmos__Endpoint` | Cosmos endpoint (default `http://localhost:8081`, the emulator) |
| `Cosmos__Key` | Account key (default: the well-known public emulator key) |
| `Services__CandidateApi` / `Services__JobApi` | ApplicationService's URLs for the other services |
| `VITE_API_URL` | API base URL baked into the WebApp at build time (Azure: the route config FQDN) |

To point a service at a real Azure Cosmos DB account, set `Cosmos__Endpoint` and
`Cosmos__Key` accordingly — the code path is identical.

## Deploying to Azure

Terraform IaC for Azure Container Apps + real Cosmos DB lives in `infra/terraform/`.
The full manual walkthrough (two-pass apply, `az acr build`, verification, teardown,
costs) is in [DEPLOY.md](DEPLOY.md). Terraform state is remote (Azure Storage,
`ats-tfstate-rg`), so local applies and the CI pipeline share one state.

## CI/CD (GitHub Actions)

One pipeline per deployable unit, each triggered only by its own paths — so
changing one service builds, tests, and deploys only that service:

| Workflow | Triggers on | PR | Push to main |
|---|---|---|---|
| `candidate-service.yml` | `src/CandidateService/**` + its tests | build + test | + image → ACR → `az containerapp update` |
| `job-service.yml` / `application-service.yml` | same pattern | same | same |
| `webapp.yml` | `src/WebApp/**` | typecheck + build | + image (API URL from repo variable) → deploy |
| `infra.yml` | `infra/terraform/**` | fmt/validate/plan | terraform apply |

The three service workflows are thin wrappers around the reusable
`service-pipeline.yml`. Images are tagged with the commit SHA; Terraform ignores
image changes on the container apps (`lifecycle.ignore_changes`), so Terraform
owns the app's shape while pipelines own what's running in it. Azure auth is
passwordless (OIDC federated credentials — no secrets stored beyond IDs).

## Troubleshooting

- **UI says "Cannot reach http://localhost:5104"** — the dev-router (or the
  services behind it) isn't running, or the Cosmos emulator hasn't finished
  starting (check `docker compose logs cosmos`).
- **Port already in use** — something else owns 5100–5103, 8081, or 1234; stop it or
  change the mapping in `docker-compose.yml` / `launchSettings.json`.
- **Cosmos emulator problems** — the `vnext-preview` emulator is a preview. If it
  misbehaves, `docker compose down` and up again (data is not persisted anyway), or
  create a free-tier Azure Cosmos DB account and point the services at it.
