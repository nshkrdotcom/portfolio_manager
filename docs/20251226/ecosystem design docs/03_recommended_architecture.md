# Recommended Architecture (Multi-Lib, Hex-Core)

## Components

1. portfolio_core (Hex package)
   - Domain models and behaviors (ports)
   - Manifest engine and wiring rules
   - Pure functions and adapters interface contracts

2. portfolio_index (library or service)
   - Ecto Repo, migrations, storage schema
   - Vector store adapters and graph store adapters
   - Ingestion pipelines (docs, code, metadata)

3. portfolio_manager (app)
   - CLI, workflows, UI
   - Uses portfolio_core + portfolio_index
   - Orchestrates ingestion and retrieval

4. rag_ex (dependency)
   - Router, retrievers, pipelines, agent tooling
   - Used behind adapters in portfolio_index

## Boundary Rules

- portfolio_core must have no Ecto, no provider SDKs, and no filesystem access.
- portfolio_index can depend on Ecto, rag_ex, and provider SDKs.
- portfolio_manager can depend on everything but should keep storage logic
  inside portfolio_index.
- rag_ex must not own storage adapters or migrations; treat it as a behavior
  library only.

## Target Responsibilities

```
portfolio_manager
  - CLI
  - workflows
  - user orchestration

portfolio_index
  - Postgres schema
  - vector store adapters
  - graph store adapters
  - ingestion pipelines
  - retrieval pipelines

portfolio_core
  - domain models
  - ports and adapters interface
  - manifest parser + validator
  - wiring rules

rag_ex
  - retrieval and agent framework
```

## System Layout

```
                +----------------------+
                |  portfolio_manager   |
                |  CLI / workflows     |
                +----------+-----------+
                           |
                           v
                +----------+-----------+
                |   portfolio_core     |
                | ports + manifests    |
                +----------+-----------+
                           |
                           v
                +----------+-----------+
                |  portfolio_index     |
                | storage + pipelines  |
                +----------+-----------+
                           |
              +------------+------------+
              |                         |
              v                         v
        Postgres/pgvector           Graph DB

                rag_ex provides retrievers, pipelines, agents
```

## Key Design Decisions

- portfolio_core defines the ports and is the only place with stable APIs.
- portfolio_index owns the DB and all schema/migrations.
- portfolio_manager is the UX layer and can be swapped or extended.
- rag_ex is a dependency, not a core. Adapters wrap it.

## Package Naming (suggested)

- portfolio_core (Hex) - domain + ports + manifest engine
- portfolio_index (Hex) - ingestion + storage adapters
- portfolio_manager (app) - CLI + workflows + orchestration
- portfolio_agents (optional) - agentic workflows and tool packs

## Why This Is The Right Shape

- Stable core contracts allow infinite expansion of adapters.
- Manifest-driven wiring makes system configurations explicit and reviewable.
- Multiple storage engines can be used without reworking the core.
- Allows shipping a reusable hex core without bundling DB logic.

## Required Ports (Core)

- RepoRegistryPort (list repos, metadata)
- DocumentStorePort (docs and file content)
- VectorStorePort (embeddings, semantic search)
- GraphStorePort (entities, edges, communities)
- ChunkerPort (chunking strategies)
- EmbedderPort (model selection, embeddings)
- RetrieverPort (semantic/hybrid/graph retrieval)
- PipelinePort (ingest/query pipeline execution)
- ManifestPort (manifest read, validate, resolve)
- AuditPort (provenance and change tracking)

## Data Ownership

- portfolio repo (git): human-authored metadata and summaries
- index stores (DBs): machine-generated chunks, embeddings, and graph facts
- caches (local): query results, embeddings, pipeline traces

## Adapters (Index Layer)

- VectorStorePgvectorAdapter (portfolio_index; wraps rag_ex vector store behavior)
- VectorStoreQdrantAdapter (future)
- GraphStorePgAdapter (portfolio_index; can reuse rag_ex GraphStore.Pgvector schema)
- GraphStoreNeo4jAdapter (future)
- TripleStoreRocksAdapter (portfolio_index; wraps triple_store, extracted from rag_ex)
- ChunkerRagExAdapter (rag_ex chunking strategies)
- EmbedderGeminiAdapter (rag_ex router)
- RetrieverHybridAdapter (rag_ex retrievers + reranker)

## Retrieval Modes

- Semantic only (fast, simple)
- Hybrid (semantic + fulltext)
- Graph local (entity expansion)
- Graph global (community summaries)
- Graph hybrid (local + global)

## Manifest-Driven Wiring

Manifests define which adapters are used per environment:

- local-dev: Postgres + pgvector
- local-neo: Postgres + Neo4j graph store
- cloud-qdrant: Qdrant vector store + Neo4j graph store
