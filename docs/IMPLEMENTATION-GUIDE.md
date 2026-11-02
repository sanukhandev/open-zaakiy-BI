# Open Zaakiy BI — Agentic RAG Implementation Guide

Reference: https://n8n.io/workflows/4827-ai-powered-whatsapp-chatbot-for-text-voice-images-and-pdf-with-rag/

## 1. Scope and status

This starter adapts the source template's ingestion / retrieval / request-response ideas, not its WhatsApp channel or internal AI Agent node.

Included: an **importable, disabled n8n internal test gateway** with a webhook, schema check, HTTP delegation to a backend API, and HTTP response. It contains no secrets.

Not included or implemented in this repository: Fastify API, LangGraph runtime, Foundry deployment, PostgreSQL schema, OCR worker, Salesforce connector, customer UI, and any live end-to-end verification. Do not represent this gateway as a complete assistant.

## 2. Recommended backend-first architecture

Interactive production path:

    Customer UI -> authenticated Fastify API -> Python LangGraph ->
      Foundry GPT-5.4 + authorized PostgreSQL/pgvector retrieval ->
      independent evidence checks -> Fastify response/persistence -> UI

Asynchronous integrations:

    Fastify transactional outbox -> worker -> authenticated n8n ->
      CRM / notifications -> signed callback -> Fastify

Documents:

    Fastify upload -> quarantine/private object storage -> ingestion worker ->
      native PDF/DOCX extraction or Azure Document Intelligence OCR ->
      tenant-private metadata/chunks/summary -> authorization-aware retrieval

Use n8n only for external workflow integration and optional internal test requests. Direct customer chat through n8n adds failure points without improving grounding.

## 3. Import n8n workflow

1. In n8n, import ../n8n/businessflow-n8n-agentic-rag-gateway.json.
2. Create an inbound Header Auth credential for the webhook node with a long random token.
3. Create a DIFFERENT outbound HTTP Header Auth credential for the backend call.
4. Replace the placeholder URL http://api:3000/internal/v1/agentic/turn with the actual internal API route. It is a proposed route; it is not verified to exist.
5. Restrict the n8n test webhook and backend network routes to internal Docker networking; do NOT publicly expose the gateway or its credential.
6. Keep execution payload persistence disabled, and test with synthetic tenants/customers before activating.

The Code node validates input shape ONLY. Fastify must authenticate the caller; bind tenant, customer, and conversation ownership to trusted identity; check replay/idempotency; and apply consent/eligibility rules.

## 4. Proposed API contract

POST /internal/v1/agentic/turn

Proposed request:

    {
      "tenantId": "tenant-uuid",
      "customerId": "customer-uuid",
      "conversationId": null,
      "clientMessageId": "unique-client-message-id",
      "text": "Which company formation documents do I need?",
      "documentIds": []
    }

Proposed successful response:

    {
      "conversationId": "conversation-uuid",
      "messageId": "assistant-message-uuid",
      "status": "answered",
      "answer": "The currently approved checklist requires ...",
      "citations": [
        {
          "documentId": "approved-document-id",
          "versionId": "version-id",
          "chunkId": "chunk-id",
          "page": 2
        }
      ],
      "unsupportedClaims": [],
      "pendingAction": null
    }

For missing evidence use status "insufficient_evidence" with an honest abstention or a focused clarification, never an invented source. Apply standard 400/401/403/409/429/5xx responses. The n8n demo gateway does not yet propagate all backend failures as structured HTTP errors: implement and test that before production usage.

Input tenantId, customerId, conversationId and documentIds are untrusted even when structurally valid. Check each one server-side against authenticated authorization. Never post raw uploaded file bytes to this gateway.

## 5. LangGraph design

Recommended graph:

    load_authorized_context
      -> classify_intent
      -> route(knowledge | workflow | ordinary_chat | unknown)
      -> retrieve_knowledge_or_read_authoritative_state
      -> draft_structured_response
      -> validate_evidence_and_citations
      -> route(answer | abstain | clarify | propose_action)
      -> persist_turn
      -> update_summary_if_needed

- Knowledge questions: query only approved active tenant sources and authorized private customer document chunks. Preserve document ID, version ID, chunk ID and page provenance.
- Workflow questions: fetch authoritative CRM/journey state; do not infer stage completion or user consent from model text or summaries.
- Ordinary conversation: answer naturally; do not force citations for greetings.
- Unknown or unsupported questions: clarify or abstain rather than fabricate.
- Response validation: confirm that each *material factual claim* has retrievable supporting spans or trusted structured business state. A second LLM opinion alone is not a proof of truth.
- Agent tool calls are proposals, never permission to mutate business state. Fastify applies authorization, eligibility and action confirmation.

Use deterministic routing for unambiguous commands, LLM classification for ambiguous conversational language, and hybrid retrieval/reranking only where evaluation indicates benefit.

## 6. Foundry setup

Configure actual Azure resource endpoints and DEPLOYMENT names; do not assume model IDs and deployment aliases match:

    AZURE_FOUNDRY_ENDPOINT=<actual compatible endpoint>
    AZURE_FOUNDRY_CHAT_DEPLOYMENT=<GPT-5.4 deployment name>
    AZURE_FOUNDRY_EMBEDDING_DEPLOYMENT=<embedding deployment name>
    EMBEDDING_DIMENSIONS=3072
    DOCUMENT_INTELLIGENCE_ENDPOINT=<OCR resource endpoint>

Candidate embedding model: text-embedding-3-large, with PostgreSQL pgvector vector(3072) where supported in the deployment and API. Verify embedding output dimensions match the database schema before indexing, and plan re-embedding if switching models or dimensions.

Keep API keys/tokens in secret management or private environment variables, never in exported n8n workflows, source control or client bundles. Pin SDK and API versions after verifying supported Foundry endpoints. Do not assume model availability in a region.

## 7. Memory and PostgreSQL persistence

- Persist the original append-only user/assistant turns, timestamps, tenant, conversation, clientMessageId, source citations, tool/audit events and model configuration.
- Use PostgreSQL-backed LangGraph checkpoints (e.g., the supported Postgres checkpointer for the installed LangGraph version), separate from canonical message and business records.
- Generate rolling summaries on token-budget pressure or a measured turn threshold; track last summarized source message and unresolved follow-ups.
- Summaries must preserve confirmed facts and explicit corrections, but must NEVER replace original conversation evidence, workflow state or consent records.
- Make (tenantId, conversationId, clientMessageId) idempotent and enforce ordering/stale-revision controls.
- Keep all RAG retrieval and writes tenant-scoped with PostgreSQL row-level security and service authorization.

## 8. Documents, OCR and summaries

- Upload through Fastify using streaming, size limits, MIME/content checks, malware scanning where deployed, file checksum and private storage.
- Extract text from digital PDF/DOCX natively where possible; use Azure Document Intelligence Read/Layout for scanned PDFs, photographs, tables, or low-quality extraction.
- Store per-page extraction provenance, warnings and confidence data where available.
- Summarize with original-page citations; never infer sensitive missing OCR fields. For ambiguous or low-confidence fields, explicitly request user or staff verification.
- Customer documents remain tenant/customer-private until an explicit review-and-publication process approves shared knowledge ingestion.
- For company formation workflows, attach documents to the authorized goal/stage; do not silently execute Salesforce operations based on extracted text.

## 9. CRM lead creation extension

Implement later via an authorized outbox event lead.create.requested, not through unconstrained model tool execution.

1. Collect and validate lead fields and explicit customer consent.
2. Fastify checks eligibility, tenant, stage and duplicate records, then emits a stable idempotent outbox event.
3. Worker invokes n8n with service credentials.
4. n8n uses a Salesforce connector/adapter, with retries and external idempotency/deduplication.
5. A signed backend callback records the external record identifier/receipt, verifies consistency, and advances state transactionally.

For the existing seven-stage formation journey, preserve the order: Lead Generation -> Qualification -> Account Creation -> Package Selection -> Document Upload -> Payment/Invoice -> Contract. Account creation must follow successful qualification and explicit required confirmation, never automatic for every lead.

## 10. Quality gates (proposed, not measured)

- >=85% grounded and useful conversational acceptance on a frozen, independently adjudicated golden test suite (including correct abstentions, multi-turn facts and intent).
- Zero accepted unauthorized CRM writes, high-risk unsupported claims, tenant leaks, replay attacks, or stage skips on an adversarial security suite.
- >=95% successful *eligible* lead intake and document/OCR happy-path acceptance once those features exist, with durable audit and retry-safe deduplication.
- 25-turn and 200-turn tests validate history fidelity, correction handling, citation reproducibility and restart recovery.
- Negative tests include missing knowledge, revoked documents, prompt-injection text in uploaded documents, model/provider errors, unclear OCR, duplicate webhook delivery, and upstream timeouts.

There is no achievable "never hallucinate" model guarantee. The control objective is to prevent unsupported high-risk answers from being accepted and measure failure modes.

## 11. Delivery sequence

1. Inventory existing API and schema. Establish quality and security baselines.
2. Implement one authorized LangGraph conversational path behind Fastify; keep side effects disabled.
3. Add grounded citations and independent evidence validation, Postgres messages and graph checkpoints.
4. Add private document upload, extraction/OCR and cited summaries.
5. Run adversarial/UAT evaluations until the gates are achieved.
6. Connect Salesforce lead creation via outbox + n8n with sandbox testing and signed callbacks.

## 12. Verification performed

The exported workflow is well-formed JSON with seven nodes and a connected request/validation/response path. Credentials are placeholders and it is disabled by default.

No test in a running n8n instance, deployed Fastify/LangGraph service, Azure Foundry resource, PostgreSQL instance, Document Intelligence resource or Salesforce sandbox has been performed as part of this starter. The internal API route is intentionally unimplemented here.
