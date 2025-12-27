# Manifest-Based Hex Core

## Goal

Define a reusable hexagonal core that is wired entirely by manifests. A manifest
selects adapters for each port, with explicit configuration. This allows per
environment or per project variations without code changes.

## Manifest Concept

A manifest is a declarative specification of:

- Ports (interfaces) required by the core
- Adapters that satisfy each port
- Adapter configuration (credentials, endpoints, settings)
- Pipeline definitions (ingest, query)
- Runtime defaults (embedding models, chunkers, retrievers)
- Feature flags and experimental toggles

## Example Manifest (YAML)

```yaml
version: 1
id: local-pgvector
ports:
  vector_store:
    adapter: portfolio_index.vector.pgvector
    config:
      repo: PortfolioManager.VectorStore.Repo
      table: rag_chunks
  graph_store:
    adapter: portfolio_index.graph.pgvector
    config:
      repo: PortfolioManager.VectorStore.Repo
      entity_table: graph_entities
  embedder:
    adapter: portfolio_index.embed.gemini
    config:
      model: text-embedding-004
  chunker:
    adapter: portfolio_index.chunker.rag_ex
    config:
      strategy: paragraph
  retriever:
    adapter: portfolio_index.retriever.hybrid
    config:
      mode: hybrid
      limit: 20
pipelines:
  ingest_docs:
    steps:
      - discover_docs
      - chunk
      - embed
      - store_chunks
  query:
    steps:
      - embed_query
      - retrieve
      - rerank
      - synthesize
```

## Manifest Resolution

- Manifests can be layered: base + env overrides.
- A manifest is resolved into a runtime wiring plan.
- Each adapter declares its capabilities and required settings.

### Layering Strategy

- base.yaml: common defaults
- env.local.yaml: local overrides (paths, credentials)
- env.cloud.yaml: cloud overrides (endpoints, secrets)
- workload.docs.yaml: ingestion-specific overrides

The resolver merges in order and records the merge trace for auditability.

## Manifest Engine in portfolio_core

Core responsibilities:

- Parse manifests (YAML, JSON, or Elixir map)
- Validate against schema
- Resolve adapters to modules and apply defaults
- Provide runtime wiring to the application

## Adapter Registry

Each adapter is registered with metadata:

- port_name
- module
- capabilities (supports_hybrid, supports_graph, supports_multi_index)
- config_schema

This supports validation and safe swaps.

## Runtime Wiring

- The manifest engine returns a wiring graph that is used to initialize adapters.
- Adapters are started under supervision and injected into pipelines.
- Each pipeline run is tagged with manifest_id and version for traceability.

## Manifest-Driven Ports

- VectorStorePort
- GraphStorePort
- EmbedderPort
- ChunkerPort
- RetrieverPort
- PipelinePort
- AuditPort

## Why This Matters

- Enables multi-store and multi-graph configurations without code forks
- Encourages clean separation of concerns and testability
- Provides future-proof hooks for new backends
