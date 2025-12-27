# Migration Plan

## Phase 0: Clarify Ownership

- Confirm portfolio_manager is the app layer.
- Confirm rag_ex is a library dependency.
- Agree that storage lifecycle belongs to portfolio_index.

## Phase 1: Extract portfolio_core

- Move domain structs and ports into a new Hex package.
- Keep YAML portfolio storage adapter in portfolio_manager for now.
- Introduce manifest parsing and validation in core.

Deliverable: portfolio_core published to Hex with stable ports and tests.

## Phase 2: Create portfolio_index

- Move Ecto Repo, migrations, and vector/graph adapters into portfolio_index.
- Extract Rag.GraphStore.TripleStore integration into a portfolio_index
  adapter that wraps triple_store (RocksDB).
- Provide a stable API for:
  - ingest_docs
  - search_docs
  - search_graph

Deliverable: portfolio_index can run ingestion and search independently.

## Phase 3: Wire Through Manifests

- Make portfolio_manager load a manifest and request services from core.
- Replace hardcoded settings with manifest-driven config.

Deliverable: all pipelines are manifest-selected.

## Phase 4: GraphRAG Integration

- Add graph_entities and graph_edges schema with graph_id.
- Integrate Rag.GraphRAG.Extractor and community detection.
- Provide graph retrieval modes via retriever adapter.

Deliverable: GraphRAG works for at least one repo graph.

## Phase 5: Multi-Store Support

- Add Qdrant or Pinecone adapter for vector store.
- Add Neo4j adapter for graph store.
- Add graph_id namespace strategy for multi-graph queries.

Deliverable: two vector stores and two graph stores live in manifests.

## Phase 6: Optional Service Split

- Move portfolio_index into a standalone service.
- Provide HTTP or gRPC API for portfolio_manager.

Deliverable: portfolio_manager can operate without direct DB access.

## Migration Constraints

- Keep portfolio repo as source of truth.
- Maintain current CLI behavior during transition.
- Use feature flags in manifests to enable new backends safely.
- Avoid breaking schema changes without a migration strategy.
