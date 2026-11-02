# Docker Compose: local Zaakiy BI stack

## Status and scope

This repository currently contains an **infrastructure starter**, not the application code. The base Compose stack contains four containers:

| Service | Image | Purpose | Local host port |
|---|---|---|---|
| `postgres` | `pgvector/pgvector:0.8.7-pg17` | Application data, conversation records, vector retrieval, n8n DB | None (internal) |
| `n8n` | `docker.n8n.io/n8nio/n8n:2.45.7` | CRM and integration workflow editor/orchestrator | 5678 on 127.0.0.1 |
| `n8n-runner` | `n8nio/runners:2.45.7` | Isolated Code-node execution; pinned to same n8n version | None |
| `seaweedfs` | `chrislusf/seaweedfs:4.51` | Local S3-compatible storage for private customer documents | 8333 on 127.0.0.1 |

**Not bundled:** Azure Foundry GPT-5.4, Azure Foundry embedding deployments, Azure Document Intelligence OCR, and Salesforce. They are cloud/external services, not containers.

**Not implemented here:** Fastify API, LangGraph engine, ingestion/outbox worker, auth/tenant authorization, RAG response verification, OCR, Salesforce integration, or the application DB schema. `compose.apps.example.yml` documents the future three-container API/agent/worker setup but requires real images. It is **not runnable by itself**.

## First run

Install Docker Engine with Docker Compose v2, then:

```bash
git clone https://github.com/sanukhandev/open-zaakiy-BI.git
cd open-zaakiy-BI
cp .env.example .env
# Replace ALL 'change-me' values in .env with strong random values.
# Example generator: openssl rand -hex 32
docker compose config --quiet
docker compose up -d
docker compose ps
```

Open n8n at **http://localhost:5678** and create an owner account. Import `n8n/businessflow-n8n-agentic-rag-gateway.json` manually. Configure inbound and outbound **separate Header Auth** credentials. Do **not** activate the webhook yet: its target `http://api:3000/internal/v1/agentic/turn` is a **proposed endpoint** and there is currently no API service in the base stack.

The n8n editor and SeaweedFS S3 API are published to localhost only, not exposed to your local network. The PostgreSQL port is not published. All services share the private Compose bridge network called `backend`.

## Addresses inside Docker

- App PostgreSQL: `postgres:5432`, database `zaakiy`, login `zaakiy_app`, password `APP_DB_PASSWORD`.
- Database superuser: `zaakiy_admin` (maintenance/bootstrap **only**, never use in normal application services).
- n8n PostgreSQL: `postgres:5432`, database `n8n`, login `n8n`, password `N8N_DB_PASSWORD`.
- n8n: `http://n8n:5678`.
- n8n external runner: connects to `http://n8n:5679`.
- S3 API: `http://seaweedfs:8333`, bucket `zaakiy-documents`, configured access key and secret.
- **Never use localhost from one container to access another container**.

PostgreSQL initializes the vector extension and dedicated `zaakiy_app` / `n8n` login roles on first database creation only. The `zaakiy_app` role can create application objects in the app's schema, but this is NOT row-level security or tenant access control.

## Smoke tests after starting

```bash
# Vector extension is created:
docker compose exec -T postgres psql -U zaakiy_admin -d zaakiy -c "SELECT extname FROM pg_extension WHERE extname='vector';"

# Isolated databases are created:
docker compose exec -T postgres psql -U zaakiy_admin -d postgres -c "SELECT datname FROM pg_database WHERE datname IN ('zaakiy','n8n');"

# Web UI: 200 or redirect to onboarding:
curl -I http://localhost:5678

# S3: unauthenticated access should NOT list objects; 403 is acceptable:
curl -s -o /dev/null -w '%{http_code}\n' http://localhost:8333/

docker compose logs --tail=50 postgres n8n n8n-runner seaweedfs
```

For an authenticated bucket check with AWS CLI:

```bash
# Use the S3 credentials from your private .env (do not paste or commit them).
AWS_ACCESS_KEY_ID=YOUR_LOCAL_S3_KEY AWS_SECRET_ACCESS_KEY=YOUR_PRIVATE_SECRET \
  aws --endpoint-url http://localhost:8333 s3 ls s3://zaakiy-documents/
```

## Optional app/agent/worker extension

When **real images have been implemented and built** for Fastify, LangGraph and the background worker, configure their image names and actual Azure deployments in your local `.env`:

```bash
docker compose -f docker-compose.yml -f compose.apps.example.yml config --quiet
docker compose -f docker-compose.yml -f compose.apps.example.yml up -d
```

The optional overlay defines `api:3000`, `agent:8000`, and `worker`, with shared database, document storage and Azure environment settings. These are proposed service contracts until matched to actual source code; enabling the overlay before creating images fails.

The **production chat path** should be UI → Fastify → LangGraph/Foundry → authorized PostgreSQL/pgvector → validated citations → persistence. n8n handles CRM integrations and approved external actions, not primary LLM inference or customer authentication. No Redis, Elasticsearch or MongoDB is needed for this initial architecture.

## Operational constraints

- This is a **local developer stack**. `N8N_SECURE_COOKIE=false` and HTTP are intentional for local-only testing and are **unacceptable for a public deployment**. Protect deployed n8n with TLS, authentication and ingress restrictions. Do not publish Postgres or S3 publicly.
- SeaweedFS mini runs all storage components in a single local container. For production, prefer Azure Blob Storage or a properly operated, encrypted, backed-up object storage cluster.
- Never store real sensitive customer documents until per-tenant access controls, scanning and data retention/deletion processes are implemented.
- Keep `N8N_ENCRYPTION_KEY`, `N8N_RUNNERS_AUTH_TOKEN` and all DB/S3/API credentials private. Never commit `.env` or a generated Compose config containing secrets.
- The database bootstrap runs only on the **first** creation of the postgres volume. Changing passwords in `.env` later does not rotate the existing DB roles; use explicit `ALTER ROLE` statements or reinitialize disposable volumes.
- Back up PostgreSQL and n8n volumes before upgrading. Pin n8n runner and n8n at **identical versions**.
- For `text-embedding-3-large` 3,072-dimensional vectors, evaluate indexing constraints; full `vector(3072)` storage works, but standard pgvector ANN `vector` indexes have dimensional limits. Consider `halfvec` expression indexes or a dimension-reduced embedding deployment.
- Azure deployment names and endpoints depend on the actual Azure resource. Model names alone are not valid deployment configuration.

## Backup / shutdown

```bash
# Store this backup securely; it may contain sensitive data:
docker compose exec -T postgres pg_dump -U zaakiy_admin -d zaakiy > zaakiy-backup.sql
docker compose down
# DANGER: irreversible local development data deletion:
docker compose down --volumes
```

## Verification and remaining work

Static file checks: YAML parse, service/dependency/network wiring and shell syntax. The pull request includes a GitHub Actions check executing `docker compose config --quiet` for both the base stack and overlay.

**No runtime container test has been executed in the authoring environment** because Docker Engine is unavailable. Startup, real credentials, security hardening, Foundry API calls, OCR, CRM and production readiness remain unverified.

References:

- n8n with PostgreSQL: https://github.com/n8n-io/n8n-hosting/tree/main/docker-compose/withPostgres
- n8n task runners: https://docs.n8n.io/hosting/configuration/task-runners/
- pgvector: https://github.com/pgvector/pgvector
- SeaweedFS mini: https://github.com/seaweedfs/seaweedfs/wiki/Quick-Start-with-weed-mini
