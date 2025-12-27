# Portfolio Manager RAG System Plan (2025-12-25)

## Goals
- Track all git repos under `~/p/g/n` and `~/p/g/North-Shore-AI`.
- Ingest legacy docs that live inside repos (README, .github/README, docs/) without moving them.
- Provide RAG queries that use repo metadata + doc content + relationships.
- Keep the portfolio repo as the auditable source of truth while enabling fast semantic search.

## Non-Goals (for now)
- Centralized docs in `~/p/g/n/portfolio` (planned later).
- Fully automatic background sync; manual or scheduled runs are fine.
- Rewriting existing repo docs or forcing migration.

## Current Baseline (observed in code)
- Portfolio data lives in YAML/Markdown under a portfolio repo (`config.yml`, `registry.yml`, `relationships.yml`, `repos/{id}/context.yml`, `notes.md`, `decisions/`).
- Scan is git-based: only git repos are discovered.
- RAG uses `rag_ex` via `PortfolioManager.Rag` and embeddings are computed on demand.
- `semantic_search/3` currently embeds only repo metadata + notes + decisions.
- There is no built-in doc ingestion pipeline.

## Target Architecture (hybrid, advanced, but incremental)
1) Source of truth (versioned):
   - Portfolio repo holds structured metadata, doc summaries, and relationship context.
2) Relational index (fast filtering):
   - Postgres for repo/doc metadata, file manifests, and chunk references.
3) Vector index (semantic recall):
   - Embeddings for doc chunks with metadata filters (repo, path, type, commit).
4) Context graph (reasoning):
   - Quadruples or named-graph triples with evidence/provenance.

The system should work end-to-end even if only layers 1 and 3 are enabled at first.

## Knowledge Representation (advanced)
- Use quadruples: (subject, predicate, object, context).
- Context contains provenance: source path, repo id, commit sha, chunk id, extractor, and confidence.
- Multiple graphs are expected (per repo, per domain). A meta-graph links them.

Example context record (pseudo):
- s: repo:nshkrdotcom
  p: documents
  o: doc:README#intro
  ctx:
    graph: repo:nshkrdotcom
    source_path: README.md
    commit: abc123
    chunk_id: chunk-07
    extractor: doc_ingest_v1
    confidence: 0.82

## Proposed Storage Layout
Portfolio repo (versioned):
- `config.yml`
- `registry.yml`
- `relationships.yml`
- `repos/{id}/context.yml`
- `repos/{id}/notes.md`
- `repos/{id}/decisions/*.md`
- `repos/{id}/docs/index.yml` (doc metadata + summaries)
- `repos/{id}/docs/summary.md` (optional per-repo summary)
- `graph/facts.yml` (quadruples, evidence pointers)

Local-only state (gitignored):
- `.portfolio/cache/index.db` (existing)
- `.portfolio/docs/chunks/{chunk_id}.md` (raw chunk text, optional)
- `.portfolio/vector/` (local metadata for pgvector sync, optional)

Note: keep raw doc content out of git if it is large; store references + summaries instead.

## Doc Ingestion Strategy (legacy docs stay in repos)
Scope:
- Only index Elixir projects.

Default includes (legacy workflow):
- `docs/**/*.md`

Excludes:
- `.git`, `node_modules`, `deps`, `_build`, `priv`, `assets`, `**/vendor/**`

Pipeline:
1) Discover tracked repos (from portfolio registry).
2) For each repo, find doc files via include/exclude patterns.
3) Read text, normalize (strip boilerplate), compute content hash.
4) Chunk by headings and size (ex: 800-1200 tokens, overlap 100).
5) Summarize per doc and per repo (short, factual).
6) Write metadata to `repos/{id}/docs/index.yml`.
7) Store chunk text locally and embed into vector index.
8) Update `context.yml` computed fields with doc counts, last update, and top summary.

## Retrieval Strategy (RAG)
- Add tool: `search_docs` (vector search across doc chunks).
- Add tool: `get_doc` (fetch doc summaries + metadata).
- Update `PortfolioManager.semantic_search/3` to incorporate doc summaries or doc chunk hits.
- Agent prompt should mention doc tools explicitly.

## Phased Implementation Plan

### Phase 0: Preflight and Baseline
- Set `PORTFOLIO_DIR=~/p/g/n/portfolio`.
- Initialize portfolio repo and git init.
- Add scan dirs: `~/p/g/n`, `~/p/g/North-Shore-AI`.
- Run `mix portfolio.scan` and `mix portfolio.sync --views`.

Deliverables:
- Portfolio repo created and populated with repos and views.

### Phase 1: Minimal Working Doc Ingestion (MVP)
- Add a new config section to `config.yml`:
  - `docs.include_patterns`, `docs.exclude_patterns`, `docs.max_size`.
- Implement `PortfolioManager.Docs.Ingest` (new module).
- Add `mix portfolio.docs ingest` (new CLI task).
- Store per-repo doc summaries and metadata in `repos/{id}/docs/index.yml`.
- Update `semantic_search/3` to include doc summaries in the searchable content.

Deliverables:
- `mix portfolio.docs ingest` populates doc metadata for tracked repos.
- RAG queries and semantic search mention docs.

### Phase 2: Vector Index for Docs
- Use Postgres + pgvector as the vector backend.
- Implement `PortfolioManager.VectorStore` (create/update/search).
- Store chunk embeddings and metadata; keep full chunk text local.
- Add a `search_docs` tool for the agent.

Deliverables:
- Doc search returns relevant chunks with provenance.

### Phase 3: Context Graph (Quadruples)
- Add a `graph/` store with quadruples and evidence links.
- Implement `PortfolioManager.Graph.Context` to add/query facts.
- Allow relationships to reference graph nodes (repo <-> doc <-> chunk).

Deliverables:
- Structured, queryable context graph with evidence per fact.

### Phase 4: Workflows and Automation
- Add workflow `doc-ingest.yml` in `priv/workflows/`:
  - Finds repos, ingests docs, refreshes vector index.
- Add workflow `doc-review.yml`:
  - Agent summarizes large docs and proposes tags/relationships.
- Add `mix portfolio.run doc-ingest` to keep system updated.

Deliverables:
- One-command refresh and review pipeline.

### Phase 5: Centralized Docs (future)
- Add `docs/` under the portfolio repo for centralized private docs.
- Extend ingestion to include those docs in the same pipeline.

Deliverables:
- Unified RAG over code + centralized docs.

## 12-Hour Task List (initial slice)
1) Hour 1: Confirm `PORTFOLIO_DIR`, add scan roots, run `mix portfolio.scan` and `mix portfolio.sync --views`.
2) Hour 2: Pick two Elixir repos for the first slice and add them to the portfolio registry.
3) Hour 3: Implement doc discovery limited to `docs/**/*.md` and only Elixir repos.
4) Hour 4: Add chunking (max chars + overlap) and write `repos/{id}/docs/index.yml`.
5) Hour 5: Add CLI task `mix portfolio.docs ingest` with `--repo`, `--dry-run`, `--embed`.
6) Hour 6: Wire Postgres + pgvector, create the table, and verify the vector store.
7) Hour 7: Batch embed doc chunks with Gemini and insert into pgvector.
8) Hour 8: Add `mix portfolio.docs search` and validate cross-repo retrieval.
9) Hour 9: Update `semantic_search/3` to include doc summaries.
10) Hour 10: Add delete/reingest behavior for changed docs (content hash).
11) Hour 11: Document configuration and add a runbook for ingestion.
12) Hour 12: Expand to more repos or add workflow automation.

## Acceptance Criteria (functioning system)
- All repos under both roots are tracked in the portfolio registry.
- `docs/**/*.md` content is indexed and searchable.
- `mix portfolio.ask` answers questions that cite repo docs.
- Doc metadata and summaries are stored in the portfolio repo.
- Vector search returns chunk-level results with provenance.

## Risks and Mitigations
- Large docs bloat the portfolio repo.
  - Mitigation: store only summaries and metadata in git; keep chunks local.
- Embedding costs and latency.
  - Mitigation: incremental ingestion by content hash; batch embeddings.
- Ambiguous entity names across repos.
  - Mitigation: use stable `repo_id` + path-qualified IDs in graph.

## Open Questions
- Target Postgres connection details for pgvector?
- Chunk size/overlap defaults for best doc recall?
- Should doc summaries be stored in `notes.md` or a dedicated docs index?
- Any repos to explicitly exclude from ingestion?
