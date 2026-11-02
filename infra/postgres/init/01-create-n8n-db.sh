#!/usr/bin/env bash
# PostgreSQL sources non-executable initdb.d shell files. Scope flags to a subshell.
(
  set -Eeuo pipefail
  : "${APP_DB_PASSWORD:?APP_DB_PASSWORD is required}"
  : "${N8N_DB_PASSWORD:?N8N_DB_PASSWORD is required}"
  # Runs only when the database volume is initialized for the first time.
  psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" \
    -v "app_password=$APP_DB_PASSWORD" -v "n8n_password=$N8N_DB_PASSWORD" <<'SQL'
CREATE EXTENSION IF NOT EXISTS vector;
SELECT format('CREATE ROLE zaakiy_app LOGIN PASSWORD %L', :'app_password') \gexec
SELECT format('CREATE ROLE n8n LOGIN PASSWORD %L', :'n8n_password') \gexec
GRANT CONNECT, TEMPORARY ON DATABASE zaakiy TO zaakiy_app;
GRANT USAGE, CREATE ON SCHEMA public TO zaakiy_app;
CREATE DATABASE n8n OWNER n8n;
SQL
)
