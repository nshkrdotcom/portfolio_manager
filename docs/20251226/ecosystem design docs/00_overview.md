# Ecosystem Overview and Principles

## Purpose

This document defines the long term architecture for a portfolio-scale RAG system that
can index many repositories and documents, support multiple vector stores and graph
stores, and evolve into a large ecosystem. The target is a maintainable, explicit,
hexagonal architecture where adapters can be swapped without rewriting the core.

## Vision

- A portfolio-wide knowledge system that can reason over code, docs, and metadata.
- Multiple storage backends (pgvector, Qdrant, Pinecone, Neo4j, RocksDB) can be
  used side by side, not just one at a time.
- Multiple embedding models and chunking strategies can coexist per workload.
- Retrieval can be semantic, keyword, hybrid, graph, and agentic.
- Configurations are explicit and versioned via manifest files.
- The core is a reusable Hex package published to Hex.

## Scope

- This design is larger than a single app. It describes a family of libraries and
  services that can be composed for local workflows and eventually multi-host setups.
- The immediate focus is a robust architecture, not just a minimal working demo.

## Decision Drivers

1. Long term maintainability and explicit boundaries.
2. Easy swapping of providers and storage backends.
3. Strong provenance and reproducibility of data and models.
4. Support for multi-graph and multi-vector ecosystems.
5. Iterative adoption without breaking the existing portfolio workflow.

## Key Assumptions (explicit)

- rag_ex is a library, not an application. It should remain a framework for RAG
  components, not the system of record.
- portfolio_manager is a user-facing app that orchestrates ingestion and retrieval.
- Postgres + pgvector is acceptable for phase 1 and phase 2, but is not the final
  storage story.
- GraphRAG is useful but not sufficient for all retrieval needs; hybrid pipelines
  remain necessary.
- A manifest-based hex core is the right long term model for wiring adapters and
  configurations per environment and per workload.

## Architectural Principles

- Single responsibility per component.
- Explicit ports and adapters for all external systems.
- Configurable pipelines driven by manifests, not hard-coded flows.
- Stable core domain models and versioned manifests.
- Async ingestion and query-time isolation (writes never block reads).
- Clear separation between source-of-truth, indexes, and caches.

## System Context (high level)

```
         Git repos + docs             External LLMs
                 |                           |
                 v                           v
      Ingestion Pipelines  ----->  Embeddings / Rerankers
                 |
                 v
  Index Backends (vector, graph, relational)
                 |
                 v
         Retrieval Pipelines
                 |
                 v
           Apps / Agents / CLI
```

## What Success Looks Like

- A developer can add a new graph store (Neo4j) or vector store (Qdrant)
  by shipping an adapter and updating a manifest, without touching the core.
- The system can support multiple graph namespaces, cross-graph queries,
  and graph-of-graphs traversal for large ecosystems.
- Retrieval pipelines are composable and observable, with stable metrics.
- The portfolio repo remains the auditable, human-readable source of truth.

