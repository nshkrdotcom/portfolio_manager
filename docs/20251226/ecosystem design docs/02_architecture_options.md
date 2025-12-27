# Architecture Options and Boundaries

## Option A: Monolith (Single App)

**Description**
- portfolio_manager owns everything: domain, ingestion, vector store, graph store,
  pipelines, agents, and storage schema.

**Pros**
- Fewer moving parts
- Fast iteration in early phase

**Cons**
- Tight coupling between RAG logic and portfolio domain
- Hard to swap storage backends
- Hard to publish reusable core as Hex package

## Option B: Two-Lib Model

**Description**
- portfolio_manager is the app
- rag_ex is the dependency for RAG features
- The app owns Ecto Repo and migrations

**Pros**
- Minimal new components
- Matches current state with clear responsibilities

**Cons**
- portfolio_manager becomes both product and framework
- Domain core is hard to reuse in other apps

## Option C: Three-Lib Model (Recommended)

**Description**
- portfolio_core (Hex package): domain models, ports, manifest engine
- portfolio_index (library or service): storage + ingestion + search adapters
- portfolio_manager (app): CLI, workflows, orchestration, UI
- rag_ex remains a dependency for retrieval / RAG

**Pros**
- Clean boundaries and long-term maintainability
- Core can be published to Hex for reuse
- Index layer can be swapped or scaled independently

**Cons**
- More coordination and release management
- Requires clear versioning strategy

## Option D: Service Split

**Description**
- portfolio_manager is a client app
- portfolio_indexer is a service with Postgres + graph db
- rag_ex remains a library inside the indexer

**Pros**
- Clear separation of read/write data plane
- Allows scaling and isolation

**Cons**
- Adds operational overhead
- Requires service discovery and deployment strategy

## Option E: Plugin Marketplace (overlay on C/D)

**Description**
- Adapters and pipelines are packaged as plugins
- Manifests can reference plugin versions and capabilities

**Pros**
- Encourages modular ecosystem growth
- Isolates experimental backends

**Cons**
- Requires strong versioning discipline
- Needs a registry for plugin discovery

## Decision Criteria

- Need for hexagonal, manifest-based core -> favors Option C
- Need for local-first workflows -> favors Option C over full service
- Need for multi-graph + multi-vector ecosystems -> favors Option C or D

## Recommended Choice

Option C: Three-Lib Model with a manifest-based core and a dedicated index layer.
This provides the right separation and still supports local-only operation.
