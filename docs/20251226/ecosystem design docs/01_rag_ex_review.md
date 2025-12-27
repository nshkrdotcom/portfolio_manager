# rag_ex Review (Critical)

## Summary

rag_ex is a modular RAG framework, not a RAG application. It provides
routing, embeddings, retrievers, vector store behavior, graph store behavior,
chunking strategies, pipelines, and an agent framework. It expects the consumer
app to provide an Ecto Repo and run migrations. It does not own database
lifecycle, ingestion, or domain modeling.

## What rag_ex Actually Provides

1. Router + providers
   - Multi-LLM routing (fallback, round-robin, specialist)
   - Providers for Gemini, Claude, Codex, Ollama
2. Retrieval behaviors
   - Semantic, FullText, Hybrid (RRF), Graph retrievers
3. Vector store behavior
   - Rag.VectorStore.Store behavior with pgvector implementation
   - Rag.VectorStore.Chunk schema for document chunks
4. GraphRAG
   - GraphStore behavior
   - Pgvector-backed graph store (graph_entities, graph_edges, graph_communities)
   - Graph retriever (local/global/hybrid) with traversal expansion
   - Entity extraction and community detection
   - TripleStore-backed graph store (RocksDB + RDF mapping)
     - Rag.GraphStore.TripleStore in rag_ex
     - Uses triple_store dependency for RDF storage and traversal
5. Pipelines
   - Step-based execution with caching, retries, parallel execution
6. Agent framework
   - Tool registry and multi-step tool calls
7. Conditional compilation
   - Ecto-dependent modules are only compiled if Ecto is available
   - This allows rag_ex to be used without Postgres

## Gaps and Constraints (Observed)

- rag_ex does not ship an Ecto Repo or migrations. The consumer app must do it.
- GraphStore is implemented for Postgres + pgvector and for TripleStore.
  The changelog mentions "Neo4j ready" but no Neo4j adapter exists in the codebase.
- Graph community hierarchy is incomplete. The community detector explicitly
  notes that meta-graph construction is simplified and not implemented.
- No ingestion pipeline for repos and docs. The app must do discovery, chunking,
  and storage itself.
- Vector search uses L2 distance; no built-in cosine normalization choices.
- Retriever behavior is generic and does not define domain-specific filters
  such as repo_id, path, or graph_id. The app must add those constraints.
- Rag.GraphStore.TripleStore uses an ETS-based id counter for new nodes/edges.
  Without a persisted counter or max-id scan, ids can collide after restart.
- The triple_store integration lives inside rag_ex, which is a layering
  violation for a hex architecture.

## Strengths

- Clear behavior boundaries for retrievers, vector stores, graph stores.
- Modular pipeline system that can be reused for ingestion and retrieval.
- Provides most of the core RAG logic so app code can be thin.
- Optional Ecto dependencies allow use without Postgres.
- TripleStore integration enables RDF indexing and traversal on RocksDB.

## Weaknesses for a Portfolio-Scale System

- No storage ownership means the app must define schema and migrations.
- Pgvector is a single storage choice; large-scale systems often need multiple
  vector stores and shards. rag_ex supports this via Store behavior, but no
  reference multi-store implementation exists.
- GraphRAG is valuable but incomplete for multi-graph ecosystems and very
  large graphs. The Postgres graph store is not a substitute for a graph
  database at scale.
- Agent framework is generic; it needs domain-specific tools and retrieval
  integration to be useful in portfolio_manager.
- Chunking is flexible but not attached to document lifecycle. There is no
  built-in concept of file versioning or content hashing.
- TripleStore integration does not expose SPARQL or OWL reasoning through the
  GraphStore interface; it focuses on property-graph mapping and traversal.

## Architectural Implications

- rag_ex must remain a library and never own storage adapters or schema.
- portfolio_manager needs an explicit data plane (DB + migrations) and a
  control plane (manifests, configuration, orchestration) to make rag_ex
  useful at scale.
- Rag.GraphStore.TripleStore should be extracted into portfolio_index (or a
  dedicated adapter package) and exposed behind a GraphStorePort. rag_ex
  should not depend on RocksDB directly.
- If SPARQL or OWL reasoning is required, define a separate RdfStorePort
  instead of forcing it into GraphStorePort.
- The app should implement a multi-index registry to support multiple vector
  stores and embedding models in parallel.

## Recommendation

- Keep rag_ex as the RAG kernel (router + retrievers + behaviors).
- Build a dedicated "index" layer that owns the Ecto Repo, migrations, and
  storage schema.
- Define portfolio-specific ports that hide rag_ex behind stable interfaces
  so swapping or extending rag_ex is low-risk.
