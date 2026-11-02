# Open Zaakiy BI — Agentic RAG / n8n Starter

Backend-first starter for a **grounded conversational assistant** using Azure AI Foundry, LangGraph, PostgreSQL + pgvector, and n8n for extensible external integrations.

> **Status: starter / integration design.** The checked-in n8n workflow is an **internal test gateway**, not a complete AI assistant. It delegates chat requests to a **proposed Fastify backend endpoint** that is not implemented in this repository. No live Azure, PostgreSQL, Salesforce, OCR, or end-to-end testing is claimed.

## Architecture

```text
Customer UI
    |
    v
Authenticated Fastify API -----> PostgreSQL (messages, citations, audit)
    |
    v
Python LangGraph --------------> Azure Foundry GPT-5.4
    |                           Azure Foundry embeddings
    v
Tenant-scoped RAG retrieval ---> PostgreSQL + pgvector
    |
    v
Evidence validation -----------> Answer with citations or abstain

Documents: Fastify upload -> worker -> native parsing / Azure OCR -> private storage
External actions: Fastify outbox -> worker -> n8n -> CRM / notifications
```

**Do not route production interactive chat through n8n.** Use Fastify as the policy and conversation API; use LangGraph for conversational orchestration; reserve n8n for integrations and an optional sandbox request gateway.

## Repository contents

- [n8n/businessflow-n8n-agentic-rag-gateway.json](n8n/businessflow-n8n-agentic-rag-gateway.json): importable *disabled* internal webhook -> validation -> API request -> response workflow. No WhatsApp, secrets, CRM mutation, or embedded LLM agent.
- [docs/IMPLEMENTATION-GUIDE.md](docs/IMPLEMENTATION-GUIDE.md): request contracts, configuration, evidence/grounding requirements, documents/OCR, memory, CRM extension, and acceptance gates.

## Import and configure

1. Import `n8n/businessflow-n8n-agentic-rag-gateway.json` into an **internal-only sandbox** n8n instance.
2. Configure inbound **Header Auth** on the webhook and independent outbound **Header Auth** on the HTTP Request node.
3. Change the placeholder `http://api:3000/internal/v1/agentic/turn` to a real authorized backend route once implemented.
4. Build or connect the API and LangGraph services. The workflow cannot generate answers on its own.
5. Test tenant isolation, unsupported claims, retries, and 4xx/5xx handling before enabling.

For details, read [the implementation guide](docs/IMPLEMENTATION-GUIDE.md).

## Safeguards

Never commit secrets, trust tenant IDs from request bodies, treat a model-generated tool call as authorization, or expose n8n webhook credentials publicly. User documents are private until reviewed for publication into an approved knowledge base.

## Acceptance targets (proposed, not achieved)

- >=85% grounded, useful, correctly abstaining answers on a frozen human-reviewed evaluation set.
- >=95% valid lead intake and document-processing acceptance when those integrations exist.
- Zero accepted cross-tenant leakage, unauthorized CRM writes, or critical stage-skip defects in the test suite.

This starter is **not production-ready**.
