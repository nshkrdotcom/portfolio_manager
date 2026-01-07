# Portfolio Ecosystem Architecture Overview

**Version**: 0.3.0
**Date**: December 28, 2025
**Packages**: portfolio_core, portfolio_index, portfolio_manager

---

## Table of Contents

1. [Executive Summary](#executive-summary)
2. [Package Overview](#package-overview)
3. [Portfolio Core](#portfolio-core-v020)
4. [Portfolio Index](#portfolio-index-v020)
5. [Portfolio Manager](#portfolio-manager-v030)
6. [System Integration](#system-integration)
7. [Data Flow Examples](#data-flow-examples)
8. [Configuration Guide](#configuration-guide)
9. [Deployment Considerations](#deployment-considerations)

---

## Executive Summary

The Portfolio Ecosystem is a modular Elixir framework for building intelligent code portfolio management systems with RAG (Retrieval-Augmented Generation) capabilities. It follows hexagonal architecture principles, enabling pluggable backends for storage, AI providers, and processing pipelines.

### Key Characteristics

| Attribute | Description |
|-----------|-------------|
| **Architecture** | Hexagonal (ports and adapters) |
| **Configuration** | Manifest-driven YAML with environment variable expansion |
| **Storage** | PostgreSQL + pgvector (vectors), Neo4j (graphs) |
| **AI Providers** | Gemini, Claude, OpenAI (pluggable) |
| **Processing** | Broadway-based streaming pipelines |
| **Orchestration** | DAG-based workflows, multi-provider routing |

### Package Hierarchy

```
┌─────────────────────────────────────────┐
│         portfolio_manager               │  Application Layer
│  (RAG, Router, Agent, Pipeline, CLI)    │
├─────────────────────────────────────────┤
│          portfolio_index                │  Implementation Layer
│  (Adapters, Strategies, Pipelines)      │
├─────────────────────────────────────────┤
│          portfolio_core                 │  Foundation Layer
│  (Ports, Registry, Manifest Engine)     │
└─────────────────────────────────────────┘
```

---

## Package Overview

| Package | Version | Role | Key Exports |
|---------|---------|------|-------------|
| **portfolio_core** | 0.2.0 | Framework foundation | 13 port behaviours, manifest engine, adapter registry, telemetry |
| **portfolio_index** | 0.2.0 | Concrete implementations | Pgvector, Neo4j, Gemini, Claude adapters; 4 RAG strategies; Broadway pipelines |
| **portfolio_manager** | 0.3.0 | Application layer | Router, RAG, Agent, Pipeline, Graph, CLI tasks |

---

## Portfolio Core (v0.2.0)

### Purpose

Portfolio Core provides the foundational abstractions for building flexible RAG systems. It defines **port specifications** (Elixir behaviours) that establish contracts for adapter implementations, enabling storage backends, AI providers, and processing components to be swapped via configuration.

### Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           PORTFOLIO CORE v0.2.0                             │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                        PORT SPECIFICATIONS                          │   │
│  │  (Elixir Behaviours - contracts for adapter implementations)        │   │
│  ├─────────────────────────────────────────────────────────────────────┤   │
│  │                                                                     │   │
│  │  STORAGE PORTS                         AI/ML PORTS                  │   │
│  │  ┌─────────────┐  ┌─────────────┐     ┌─────────────┐  ┌─────────┐ │   │
│  │  │ VectorStore │  │ GraphStore  │     │  Embedder   │  │   LLM   │ │   │
│  │  │ ─────────── │  │ ─────────── │     │ ─────────── │  │ ─────── │ │   │
│  │  │ •create_idx │  │ •create_node│     │ •embed      │  │•complete│ │   │
│  │  │ •store      │  │ •create_edge│     │ •embed_batch│  │•stream  │ │   │
│  │  │ •search     │  │ •query      │     │ •dimensions │  │•model_  │ │   │
│  │  │ •delete     │  │ •neighbors  │     │             │  │  info   │ │   │
│  │  └─────────────┘  └─────────────┘     └─────────────┘  └─────────┘ │   │
│  │                                                                     │   │
│  │  ┌─────────────┐  ┌─────────────┐     ┌─────────────┐  ┌─────────┐ │   │
│  │  │DocumentStore│  │    Cache    │     │   Chunker   │  │Retriever│ │   │
│  │  │ ─────────── │  │ ─────────── │     │ ─────────── │  │ ─────── │ │   │
│  │  │ •store      │  │ •get/put    │     │ •chunk      │  │•retrieve│ │   │
│  │  │ •get        │  │ •delete     │     │ •estimate   │  │•strategy│ │   │
│  │  │ •list       │  │ •stats      │     │             │  │         │ │   │
│  │  └─────────────┘  └─────────────┘     └─────────────┘  └─────────┘ │   │
│  │                                                                     │   │
│  │  INFRASTRUCTURE PORTS (v0.2.0)                                      │   │
│  │  ┌─────────────┐  ┌─────────────┐     ┌─────────────┐  ┌─────────┐ │   │
│  │  │   Router    │  │  Pipeline   │     │    Agent    │  │  Tool   │ │   │
│  │  │ ─────────── │  │ ─────────── │     │ ─────────── │  │ ─────── │ │   │
│  │  │ •route      │  │ •execute    │     │ •run        │  │•execute │ │   │
│  │  │ •register   │  │ •validate   │     │ •tools      │  │•name    │ │   │
│  │  │ •health     │  │ •cacheable? │     │ •exec_tool  │  │•params  │ │   │
│  │  └─────────────┘  └─────────────┘     └─────────────┘  └─────────┘ │   │
│  │                                                                     │   │
│  │  ┌─────────────┐                                                    │   │
│  │  │  Reranker   │  Router Strategies: fallback, round_robin,        │   │
│  │  │ ─────────── │                     specialist, cost_optimized    │   │
│  │  │ •rerank     │                                                    │   │
│  │  └─────────────┘                                                    │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                             │
│  ┌──────────────────────┐    ┌──────────────────────┐                      │
│  │   MANIFEST ENGINE    │    │   ADAPTER REGISTRY   │                      │
│  │ ──────────────────── │    │ ──────────────────── │                      │
│  │                      │    │                      │                      │
│  │  manifest.yml ───────┼───▶│  ETS Table           │                      │
│  │  ┌────────────────┐  │    │  :portfolio_adapters │                      │
│  │  │ version: "1.0" │  │    │                      │                      │
│  │  │ adapters:      │  │    │  Registry.get(:port) │                      │
│  │  │   vector_store:│  │    │  → {Module, Config}  │                      │
│  │  │     adapter:...│  │    │                      │                      │
│  │  │ router:        │  │    │  Features:           │                      │
│  │  │   strategy:... │  │    │  • Health tracking   │                      │
│  │  └────────────────┘  │    │  • Call metrics      │                      │
│  │                      │    │  • Capability query  │                      │
│  │  ${ENV_VAR:-default} │    │                      │                      │
│  │  NimbleOptions valid │    │                      │                      │
│  └──────────────────────┘    └──────────────────────┘                      │
│                                                                             │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                          TELEMETRY                                   │   │
│  │  [:portfolio_core, :adapter, :call, :start/:stop/:exception]        │   │
│  │  [:portfolio_core, :manifest, :loaded/:reload/:error]               │   │
│  │  [:portfolio_core, :registry, :register/:lookup]                    │   │
│  │  [:portfolio_core, :router, :route, :start/:stop]                   │   │
│  │  [:portfolio_core, :agent, :run, :start/:stop]                      │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Port Specifications (13 Behaviours)

#### Storage Ports

| Port | Purpose | Key Callbacks |
|------|---------|---------------|
| **VectorStore** | Vector embeddings with similarity search | `create_index/2`, `store/4`, `search/4`, `delete/2` |
| **GraphStore** | Knowledge graphs with nodes/edges | `create_node/2`, `create_edge/2`, `query/3`, `get_neighbors/3` |
| **DocumentStore** | Source document storage | `store/4`, `get/2`, `list/2`, `search_metadata/2` |
| **Cache** | Result caching abstraction | `get/2`, `put/3`, `delete/2`, `stats/1` |

#### AI/ML Ports

| Port | Purpose | Key Callbacks |
|------|---------|---------------|
| **Embedder** | Text-to-vector conversion | `embed/2`, `embed_batch/2`, `dimensions/1` |
| **LLM** | Language model completions | `complete/2`, `stream/2`, `model_info/1` |
| **Chunker** | Document splitting | `chunk/3`, `estimate_chunks/2` |
| **Retriever** | Multi-source retrieval | `retrieve/3`, `strategy_name/0`, `required_adapters/0` |
| **Reranker** | Result re-scoring | `rerank/3`, `model_name/0` |

#### Infrastructure Ports (v0.2.0)

| Port | Purpose | Key Callbacks |
|------|---------|---------------|
| **Router** | Multi-provider LLM routing | `route/2`, `register_provider/1`, `health_check/1` |
| **Pipeline** | Workflow step definitions | `execute/2`, `validate_input/1`, `cacheable?/0` |
| **Agent** | Tool-using agents | `run/2`, `available_tools/0`, `execute_tool/1` |
| **Tool** | Individual executable tools | `name/0`, `description/0`, `parameters/0`, `execute/1` |

### Manifest Engine

The manifest engine provides YAML-based configuration with:

- **Environment variable expansion**: `${VAR}` (required) or `${VAR:-default}` (optional)
- **Schema validation**: NimbleOptions-based validation
- **Hot reload**: Runtime manifest reloading via `PortfolioCore.reload_manifest()`
- **Adapter wiring**: Automatic registration of adapters with the registry

**Example Manifest:**

```yaml
version: "1.0"
environment: production

adapters:
  vector_store:
    adapter: PortfolioIndex.Adapters.VectorStore.Pgvector
    config:
      dimensions: 768
      metric: cosine
      index_type: hnsw

  embedder:
    adapter: PortfolioIndex.Adapters.Embedder.Gemini
    config:
      model: text-embedding-004
      api_key: ${GEMINI_API_KEY}

  llm:
    adapter: PortfolioIndex.Adapters.LLM.Anthropic
    config:
      model: claude-sonnet-4-20250514
      api_key: ${ANTHROPIC_API_KEY}

router:
  strategy: specialist
  health_check_interval: 30000
  providers:
    - name: gemini
      module: PortfolioIndex.Adapters.LLM.Gemini
      capabilities: [generation, code, long_context]
      priority: 1
      cost_per_token: 0.0001
```

### Adapter Registry

The ETS-backed registry provides:

```elixir
# Registration
PortfolioCore.Registry.register(:vector_store, MyAdapter, config, %{
  capabilities: [:semantic_search, :batch_insert]
})

# Lookup
{:ok, %{module: module, config: config}} = PortfolioCore.Registry.get(:vector_store)

# Health management
PortfolioCore.Registry.mark_unhealthy(:llm)
PortfolioCore.Registry.health_status(:llm)  # => :unhealthy

# Metrics
{:ok, metrics} = PortfolioCore.Registry.metrics(:vector_store)
# => %{call_count: 1542, error_count: 3, error_rate: 0.002}
```

---

## Portfolio Index (v0.2.0)

### Purpose

Portfolio Index provides production-ready implementations of portfolio_core ports, including adapters for PostgreSQL/pgvector, Neo4j, Gemini, Claude, and advanced RAG strategies with Broadway-based processing pipelines.

### Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                          PORTFOLIO INDEX v0.2.0                             │
│                    (Implements PortfolioCore Ports)                         │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                           ADAPTERS                                   │   │
│  ├─────────────────────────────────────────────────────────────────────┤   │
│  │                                                                     │   │
│  │  STORAGE                              AI/ML                         │   │
│  │  ┌─────────────────────┐             ┌─────────────────────┐       │   │
│  │  │   Pgvector          │             │     Embedders       │       │   │
│  │  │   (PostgreSQL)      │             │ ┌─────────────────┐ │       │   │
│  │  │                     │             │ │ Gemini          │ │       │   │
│  │  │ Index Types:        │             │ │ text-embed-004  │ │       │   │
│  │  │ • HNSW (fast)       │             │ │ 768 dimensions  │ │       │   │
│  │  │ • IVFFlat (large)   │             │ └─────────────────┘ │       │   │
│  │  │ • Flat (exact)      │             │ ┌─────────────────┐ │       │   │
│  │  │                     │             │ │ OpenAI          │ │       │   │
│  │  │ Metrics:            │             │ │ (placeholder)   │ │       │   │
│  │  │ • cosine            │             │ └─────────────────┘ │       │   │
│  │  │ • euclidean         │             └─────────────────────┘       │   │
│  │  │ • dot_product       │                                           │   │
│  │  └─────────────────────┘             ┌─────────────────────┐       │   │
│  │                                      │        LLMs         │       │   │
│  │  ┌─────────────────────┐             │ ┌─────────────────┐ │       │   │
│  │  │      Neo4j          │             │ │ Anthropic       │ │       │   │
│  │  │   (Graph Store)     │             │ │ Claude 4 Opus   │ │       │   │
│  │  │                     │             │ │ Claude 4 Sonnet │ │       │   │
│  │  │ • Multi-graph via   │             │ │ 200K context    │ │       │   │
│  │  │   _graph_id prop    │             │ └─────────────────┘ │       │   │
│  │  │ • Cypher queries    │             │ ┌─────────────────┐ │       │   │
│  │  │ • Neighbor traversal│             │ │ Gemini          │ │       │   │
│  │  │ • Full-text search  │             │ │ gemini-flash-lite-latest│ │       │   │
│  │  └─────────────────────┘             │ │ 1M context      │ │       │   │
│  │                                      │ └─────────────────┘ │       │   │
│  │  ┌─────────────────────┐             │ ┌─────────────────┐ │       │   │
│  │  │   Document Store    │             │ │ OpenAI          │ │       │   │
│  │  │   (PostgreSQL)      │             │ │ GPT-4, etc.     │ │       │   │
│  │  │                     │             │ └─────────────────┘ │       │   │
│  │  │ • Content-addressable│            └─────────────────────┘       │   │
│  │  │ • SHA256 hashing    │                                           │   │
│  │  │ • JSONB metadata    │             ┌─────────────────────┐       │   │
│  │  └─────────────────────┘             │      Chunker        │       │   │
│  │                                      │   (Recursive)       │       │   │
│  │                                      │                     │       │   │
│  │                                      │ Formats:            │       │   │
│  │                                      │ • :plain            │       │   │
│  │                                      │ • :markdown         │       │   │
│  │                                      │ • :code             │       │   │
│  │                                      │ • :html             │       │   │
│  │                                      └─────────────────────┘       │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                             │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                     BROADWAY PIPELINES                               │   │
│  ├─────────────────────────────────────────────────────────────────────┤   │
│  │                                                                     │   │
│  │  INGESTION PIPELINE                 EMBEDDING PIPELINE              │   │
│  │  ┌─────────────────────┐           ┌─────────────────────┐         │   │
│  │  │  FileProducer       │           │  ETSProducer        │         │   │
│  │  │  (glob patterns)    │           │  (:embedding_queue) │         │   │
│  │  │        │            │           │        │            │         │   │
│  │  │        ▼            │           │        ▼            │         │   │
│  │  │  ┌──────────┐       │           │  ┌──────────┐       │         │   │
│  │  │  │ Processor│       │           │  │ Processor│       │         │   │
│  │  │  │ • read   │       │           │  │ • rate   │       │         │   │
│  │  │  │ • parse  │       │           │  │   limit  │       │         │   │
│  │  │  │ • chunk  │       │           │  │ • embed  │       │         │   │
│  │  │  └────┬─────┘       │           │  └────┬─────┘       │         │   │
│  │  │       │             │           │       │             │         │   │
│  │  │       ▼             │           │       ▼             │         │   │
│  │  │  ┌──────────┐       │           │  ┌──────────┐       │         │   │
│  │  │  │ Batcher  │───────┼──────────▶│  │ Batcher  │       │         │   │
│  │  │  │ → queue  │       │           │  │ → store  │       │         │   │
│  │  │  └──────────┘       │           │  └────┬─────┘       │         │   │
│  │  └─────────────────────┘           │       │             │         │   │
│  │                                    │       ▼             │         │   │
│  │  Rate Limiting: Hammer             │   VectorStore       │         │   │
│  │  100 req/min default               └─────────────────────┘         │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                             │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                       RAG STRATEGIES                                 │   │
│  ├─────────────────────────────────────────────────────────────────────┤   │
│  │                                                                     │   │
│  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐  ┌─────────┐ │   │
│  │  │   HYBRID     │  │  SELF-RAG    │  │   AGENTIC    │  │GRAPH-RAG│ │   │
│  │  │              │  │              │  │              │  │         │ │   │
│  │  │ Vector       │  │ 1. Assess    │  │ Tools:       │  │ 1.Entity│ │   │
│  │  │    +         │  │    need      │  │ •semantic_   │  │   extract│ │   │
│  │  │ Keyword      │  │ 2. Retrieve  │  │   search     │  │ 2.Graph │ │   │
│  │  │    ↓         │  │ 3. Generate  │  │ •keyword_    │  │   traverse│ │   │
│  │  │ RRF Fusion   │  │ 4. Critique  │  │   search     │  │ 3.Vector│ │   │
│  │  │              │  │    (1-5)     │  │ •get_context │  │   search│ │   │
│  │  │ score =      │  │ 5. Refine    │  │              │  │ 4.Weighted│ │   │
│  │  │ Σ 1/(k+rank) │  │    if needed │  │ Iterative    │  │   merge │ │   │
│  │  │              │  │              │  │ LLM loop     │  │         │ │   │
│  │  └──────────────┘  └──────────────┘  └──────────────┘  └─────────┘ │   │
│  │                                                                     │   │
│  │  Return format: %{items: [...], query, answer, strategy,           │   │
│  │                   timing_ms, tokens_used}                          │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Adapter Implementations

#### Vector Store: Pgvector

```elixir
# Create index with configuration
Pgvector.create_index("documents", %{
  dimensions: 768,
  metric: :cosine,
  index_type: :hnsw,
  options: %{m: 16, ef_construction: 64}
})

# Store with metadata
Pgvector.store("documents", "doc_001", embedding, %{
  source: "lib/my_module.ex",
  type: :elixir,
  line_start: 1,
  line_end: 50
})

# Similarity search
{:ok, results} = Pgvector.search("documents", query_embedding, 10, %{
  filter: %{type: :elixir}
})
```

#### Graph Store: Neo4j

```elixir
# Multi-graph isolation via _graph_id property
Neo4j.create_graph("codebase", %{type: :dependency})

Neo4j.create_node("codebase", %{
  labels: ["Module", "GenServer"],
  properties: %{name: "MyApp.Worker", file: "lib/worker.ex"}
})

Neo4j.create_edge("codebase", %{
  from_id: "MyApp.Worker",
  to_id: "GenServer",
  type: "IMPLEMENTS"
})

# Cypher queries with automatic graph_id injection
Neo4j.query("codebase", """
  MATCH (m:Module)-[:CALLS]->(n:Module)
  WHERE m.name = $name
  RETURN n
""", %{name: "MyApp.Worker"})
```

### RAG Strategies

| Strategy | Algorithm | Best For |
|----------|-----------|----------|
| **Hybrid** | Vector + keyword search with RRF fusion | General-purpose queries |
| **Self-RAG** | Self-critique with relevance/support/completeness scoring | Quality-critical applications |
| **Agentic** | Tool-based iterative search | Exploratory queries |
| **Graph-RAG** | Entity extraction + graph traversal | Relationship-aware queries |

---

## Portfolio Manager (v0.3.0)

### Purpose

Portfolio Manager is the application layer that provides user-facing APIs for RAG queries, multi-provider LLM routing, tool-using agents, pipeline orchestration, and CLI tools.

### Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                        PORTFOLIO MANAGER v0.3.0                             │
│                         (Application Layer)                                 │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                           CLI TASKS                                  │   │
│  ├─────────────────────────────────────────────────────────────────────┤   │
│  │                                                                     │   │
│  │  mix portfolio.ask       mix portfolio.search   mix portfolio.index │   │
│  │  ───────────────────     ──────────────────     ─────────────────── │   │
│  │  "Question?"             "search term"          /path/to/repo       │   │
│  │  --strategy self_rag     --index default        --index name        │   │
│  │  --stream                --k 10                 --extensions .ex    │   │
│  │                                                                     │   │
│  │  mix portfolio.graph                                                │   │
│  │  ───────────────────                                                │   │
│  │  stats --graph default                                              │   │
│  │  build /repo --language elixir                                      │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                        │                                    │
│                                        ▼                                    │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                        CORE MODULES                                  │   │
│  ├─────────────────────────────────────────────────────────────────────┤   │
│  │                                                                     │   │
│  │  ┌───────────────────────────────────────────────────────────────┐ │   │
│  │  │                         ROUTER                                 │ │   │
│  │  │                                                               │ │   │
│  │  │   Strategies:                                                 │ │   │
│  │  │   ┌──────────┐   ┌──────────┐   ┌──────────┐   ┌──────────┐  │ │   │
│  │  │   │ fallback │   │round_robin│  │specialist│   │cost_optim│  │ │   │
│  │  │   │ priority │   │distribute │  │capability│   │ $/token  │  │ │   │
│  │  │   └──────────┘   └──────────┘   └──────────┘   └──────────┘  │ │   │
│  │  │                                                               │ │   │
│  │  │   Features:                                                   │ │   │
│  │  │   • Automatic health monitoring                               │ │   │
│  │  │   • Priority-based provider selection                         │ │   │
│  │  │   • Capability-based routing                                  │ │   │
│  │  │   • Streaming support                                         │ │   │
│  │  │                                                               │ │   │
│  │  │   API:                                                        │ │   │
│  │  │   Router.complete(messages, opts)                             │ │   │
│  │  │   Router.stream(messages, callback, opts)                     │ │   │
│  │  └───────────────────────────────────────────────────────────────┘ │   │
│  │                                                                     │   │
│  │  ┌───────────────────────────────────────────────────────────────┐ │   │
│  │  │                           RAG                                  │ │   │
│  │  │                                                               │ │   │
│  │  │   query(question, opts)        ask(question, opts)            │ │   │
│  │  │   search(query, opts)          index_repo(path, opts)         │ │   │
│  │  │   stream_query(q, cb, opts)    stream_search(q, cb, opts)     │ │   │
│  │  │                                                               │ │   │
│  │  │   Strategies: :hybrid | :self_rag | :graph_rag | :agentic     │ │   │
│  │  └───────────────────────────────────────────────────────────────┘ │   │
│  │                                                                     │   │
│  │  ┌───────────────────────────────────────────────────────────────┐ │   │
│  │  │                          AGENT                                 │ │   │
│  │  │                                                               │ │   │
│  │  │   run(task, opts) → {:ok, answer}                             │ │   │
│  │  │                                                               │ │   │
│  │  │   Loop: Task → LLM → Tool Call? → Execute → Continue/Answer   │ │   │
│  │  │                                                               │ │   │
│  │  │   Built-in Tools:                                             │ │   │
│  │  │   • search_code(query, limit)                                 │ │   │
│  │  │   • read_file(path, start_line, end_line)                     │ │   │
│  │  │   • list_files(path, pattern)                                 │ │   │
│  │  │   • get_graph_context(entity, depth)                          │ │   │
│  │  └───────────────────────────────────────────────────────────────┘ │   │
│  │                                                                     │   │
│  │  ┌───────────────────────────────────────────────────────────────┐ │   │
│  │  │                        PIPELINE                                │ │   │
│  │  │                                                               │ │   │
│  │  │   run(:workflow, context) do                                  │ │   │
│  │  │     step :a, &func_a/1                                        │ │   │
│  │  │     step :b, &func_b/1, depends_on: [:a]                      │ │   │
│  │  │     step :c, &func_c/1, depends_on: [:b], cache: true         │ │   │
│  │  │   end                                                         │ │   │
│  │  │                                                               │ │   │
│  │  │   Features: DAG execution, caching, timeouts, telemetry       │ │   │
│  │  └───────────────────────────────────────────────────────────────┘ │   │
│  │                                                                     │   │
│  │  ┌───────────────────────────────────────────────────────────────┐ │   │
│  │  │                          GRAPH                                 │ │   │
│  │  │                                                               │ │   │
│  │  │   create_graph/2, add_node/2, add_edge/2, neighbors/3         │ │   │
│  │  │   query/3, stats/1, build_dependency_graph/3                  │ │   │
│  │  │                                                               │ │   │
│  │  │   Languages: Elixir (mix.exs), Python (requirements.txt)      │ │   │
│  │  └───────────────────────────────────────────────────────────────┘ │   │
│  │                                                                     │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                             │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                      SUPERVISION TREE                                │   │
│  ├─────────────────────────────────────────────────────────────────────┤   │
│  │                                                                     │   │
│  │   PortfolioManager.Application                                      │   │
│  │   ├── PortfolioCore.Registry                                        │   │
│  │   ├── PortfolioManager.Repo (if start_repo: true)                   │   │
│  │   ├── PortfolioManager.Domain.Registry                              │   │
│  │   ├── PortfolioManager.Router                                       │   │
│  │   ├── Ingestion Pipeline (if enabled)                               │   │
│  │   └── Embedding Pipeline (if enabled)                               │   │
│  │                                                                     │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Public API

```elixir
# RAG Queries
PortfolioManager.RAG.query("How does authentication work?", strategy: :hybrid)
PortfolioManager.RAG.ask("Explain the Router module", strategy: :self_rag)
PortfolioManager.RAG.search("GenServer", k: 10)
PortfolioManager.RAG.stream_query("What is this?", &IO.write/1)

# Repository Indexing
PortfolioManager.RAG.index_repo("/path/to/repo",
  index_id: "my_project",
  extensions: [".ex", ".exs", ".md"]
)

# Multi-Provider Routing
PortfolioManager.Router.complete(messages, strategy: :specialist, task_type: :code)
PortfolioManager.Router.stream(messages, callback, strategy: :fallback)
PortfolioManager.Router.set_strategy(:cost_optimized)

# Agent Execution
PortfolioManager.Agent.run("Find all GenServer modules and explain their purpose",
  tools: [:search_code, :read_file, :list_files],
  max_iterations: 10
)

# Pipeline Orchestration
import PortfolioManager.Pipeline

run(:analysis, %{repo: "/path"}) do
  step :scan, &scan_files/1
  step :parse, &parse_modules/1, depends_on: [:scan]
  step :analyze, &analyze_deps/1, depends_on: [:parse]
  step :report, &generate_report/1, depends_on: [:analyze], cache: true
end

# Graph Operations
PortfolioManager.Graph.build_dependency_graph("deps", "/path/to/repo", language: :elixir)
PortfolioManager.Graph.neighbors("deps", "MyApp.Worker", depth: 2)
```

---

## System Integration

```
┌────────────────────────────────────────────────────────────────────────────────┐
│                              FULL SYSTEM INTEGRATION                            │
├────────────────────────────────────────────────────────────────────────────────┤
│                                                                                │
│                              ┌─────────────────────────┐                       │
│                              │     USER / CLI          │                       │
│                              │  mix portfolio.ask      │                       │
│                              │  mix portfolio.search   │                       │
│                              │  mix portfolio.index    │                       │
│                              └───────────┬─────────────┘                       │
│                                          │                                     │
│  ┌───────────────────────────────────────┼──────────────────────────────────┐  │
│  │                                       ▼                                  │  │
│  │  ┌────────────────────────────────────────────────────────────────────┐ │  │
│  │  │                   PORTFOLIO MANAGER (v0.3.0)                       │ │  │
│  │  │                                                                    │ │  │
│  │  │   ┌──────────┐    ┌──────────┐    ┌──────────┐    ┌──────────┐   │ │  │
│  │  │   │  Router  │───▶│   RAG    │◀───│  Agent   │───▶│ Pipeline │   │ │  │
│  │  │   └────┬─────┘    └────┬─────┘    └────┬─────┘    └────┬─────┘   │ │  │
│  │  │        │               │               │               │         │ │  │
│  │  │        └───────────────┴───────────────┴───────────────┘         │ │  │
│  │  │                                │                                  │ │  │
│  │  └────────────────────────────────┼──────────────────────────────────┘ │  │
│  │                                   │                                    │  │
│  │                                   ▼                                    │  │
│  │  ┌────────────────────────────────────────────────────────────────────┐│  │
│  │  │                   PORTFOLIO INDEX (v0.2.0)                         ││  │
│  │  │                                                                    ││  │
│  │  │   RAG STRATEGIES              BROADWAY PIPELINES                   ││  │
│  │  │   ┌────────────────────┐      ┌────────────────────┐              ││  │
│  │  │   │ Hybrid │ Self-RAG │      │    Ingestion       │              ││  │
│  │  │   │ Agentic│ Graph    │      │    Embedding       │              ││  │
│  │  │   └─────────┬──────────┘      └─────────┬──────────┘              ││  │
│  │  │             │                           │                         ││  │
│  │  │             ▼                           ▼                         ││  │
│  │  │   ┌─────────────────────────────────────────────────────────────┐││  │
│  │  │   │                        ADAPTERS                             │││  │
│  │  │   │  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐   │││  │
│  │  │   │  │ Pgvector │  │  Neo4j   │  │ Gemini   │  │ Claude   │   │││  │
│  │  │   │  └────┬─────┘  └────┬─────┘  └────┬─────┘  └────┬─────┘   │││  │
│  │  │   └───────┼─────────────┼─────────────┼─────────────┼─────────┘││  │
│  │  └───────────┼─────────────┼─────────────┼─────────────┼──────────┘│  │
│  │              │             │             │             │           │  │
│  │              ▼             ▼             ▼             ▼           │  │
│  │  ┌────────────────────────────────────────────────────────────────┐│  │
│  │  │                    PORTFOLIO CORE (v0.2.0)                     ││  │
│  │  │                                                                ││  │
│  │  │   MANIFEST ENGINE              ADAPTER REGISTRY                ││  │
│  │  │   ┌───────────────────┐       ┌───────────────────┐           ││  │
│  │  │   │  manifest.yml     │──────▶│  ETS: adapters    │           ││  │
│  │  │   │  • adapters       │       │  lookup/register  │           ││  │
│  │  │   │  • router         │       │  health tracking  │           ││  │
│  │  │   │  • pipelines      │       └───────────────────┘           ││  │
│  │  │   └───────────────────┘                                       ││  │
│  │  │                                                                ││  │
│  │  │   PORT SPECIFICATIONS (13 Behaviours)                         ││  │
│  │  │   VectorStore, GraphStore, Embedder, LLM, Chunker, Router...  ││  │
│  │  └────────────────────────────────────────────────────────────────┘│  │
│  │                                                                    │  │
│  └────────────────────────────────────────────────────────────────────┘  │
│                                          │                               │
│                    ┌─────────────────────┼─────────────────────┐         │
│                    ▼                     ▼                     ▼         │
│          ┌──────────────────┐  ┌──────────────────┐  ┌──────────────┐   │
│          │   PostgreSQL     │  │      Neo4j       │  │ External APIs│   │
│          │   + pgvector     │  │                  │  │              │   │
│          │                  │  │   Knowledge      │  │  Gemini      │   │
│          │  Vector storage  │  │   graphs         │  │  Claude      │   │
│          │  Document store  │  │                  │  │  OpenAI      │   │
│          └──────────────────┘  └──────────────────┘  └──────────────┘   │
│                                                                          │
└──────────────────────────────────────────────────────────────────────────┘
```

---

## Data Flow Examples

### Example 1: RAG Query

```
User: mix portfolio.ask "How does authentication work?" --strategy hybrid

1. CLI parses arguments
2. Calls RAG.ask(question, strategy: :hybrid)
3. RAG.ask → RAG.query → Hybrid strategy in portfolio_index
4. Hybrid strategy:
   a. Embedder.embed(question) → query vector
   b. VectorStore.search(index, query_vector, k) → semantic results
   c. Keyword search (if available) → keyword results
   d. RRF fusion → merged results
5. RAG.ask calls Router.complete to generate answer
6. Router selects healthy provider (Gemini/Claude)
7. LLM adapter makes API call
8. Answer returned to CLI
```

### Example 2: Repository Indexing

```
User: mix portfolio.index /path/to/repo --index my_project

1. RAG.index_repo scans files matching extensions
2. For each file:
   a. Ingestion.enqueue(file_info)
3. Ingestion Pipeline (Broadway):
   a. FileProducer discovers files
   b. Processor reads, parses, chunks
   c. Batcher queues for embedding
4. Embedding Pipeline (Broadway):
   a. ETSProducer reads from queue
   b. Processor (rate-limited) generates embeddings
   c. Batcher stores in VectorStore
5. Returns {:ok, %{files_queued: N, index_id: "my_project"}}
```

### Example 3: Agent Task

```
User: Agent.run("Find all modules using GenServer")

1. Agent builds prompt with task + tool descriptions
2. Loop iteration 1:
   - LLM returns: {"tool": "search_code", "args": {"query": "GenServer"}}
   - Agent executes search_code tool
   - Results added to memory
3. Loop iteration 2:
   - LLM sees search results
   - Returns: {"tool": "read_file", "args": {"path": "lib/worker.ex"}}
   - Agent reads file, adds to memory
4. Loop iteration 3:
   - LLM has enough context
   - Returns: {"answer": "Found 5 modules using GenServer: ..."}
5. Agent returns {:ok, answer}
```

---

## Configuration Guide

### Manifest Structure

```yaml
# config/manifests/production.yml
version: "1.0"
environment: production

adapters:
  vector_store:
    adapter: PortfolioIndex.Adapters.VectorStore.Pgvector
    config:
      repo: PortfolioManager.Repo
      index_type: hnsw
      metric: cosine
      options:
        m: 16
        ef_construction: 64

  graph_store:
    adapter: PortfolioIndex.Adapters.GraphStore.Neo4j
    config:
      uri: ${NEO4J_URI}
      username: ${NEO4J_USER}
      password: ${NEO4J_PASSWORD}
      pool_size: 10

  embedder:
    adapter: PortfolioIndex.Adapters.Embedder.Gemini
    config:
      model: text-embedding-004
      api_key: ${GEMINI_API_KEY}
      dimensions: 768

  llm:
    adapter: PortfolioIndex.Adapters.LLM.Anthropic
    config:
      model: claude-sonnet-4-20250514
      api_key: ${ANTHROPIC_API_KEY}
      max_tokens: 4096

  chunker:
    adapter: PortfolioIndex.Adapters.Chunker.Recursive
    config:
      chunk_size: 1000
      chunk_overlap: 200

router:
  strategy: specialist
  health_check_interval: 30000
  providers:
    - name: gemini
      module: PortfolioIndex.Adapters.LLM.Gemini
      config:
        model: gemini-flash-lite-latest
      capabilities: [generation, code, long_context]
      priority: 1
      cost_per_token: 0.0001

    - name: claude
      module: PortfolioIndex.Adapters.LLM.Anthropic
      config:
        model: claude-sonnet-4-20250514
      capabilities: [reasoning, analysis, writing]
      priority: 2
      cost_per_token: 0.003

pipelines:
  ingestion:
    enabled: true
    concurrency: 10
    batch_size: 50

  embedding:
    enabled: true
    concurrency: 5
    rate_limit: 100

rag:
  default_strategy: hybrid

agent:
  max_iterations: 10
  timeout: 300000
```

### Application Configuration

```elixir
# config/config.exs
config :portfolio_core, :manifest,
  manifest_path: "config/manifests/#{config_env()}.yml"

config :portfolio_manager,
  env: config_env(),
  start_repo: true,
  start_router: true

config :portfolio_index,
  start_repo: true,
  start_boltx: true
```

---

## Deployment Considerations

### Required Services

| Service | Purpose | Configuration |
|---------|---------|---------------|
| PostgreSQL 15+ | Vector storage, document store | pgvector extension required |
| Neo4j 5+ | Knowledge graphs | APOC plugin recommended |
| Gemini API | Embeddings, LLM | API key required |
| Anthropic API | LLM (optional) | API key required |

### Environment Variables

```bash
# Required
DATABASE_URL=postgresql://user:pass@host/db
GEMINI_API_KEY=your-gemini-key

# Optional
ANTHROPIC_API_KEY=your-anthropic-key
NEO4J_URI=bolt://localhost:7687
NEO4J_USER=neo4j
NEO4J_PASSWORD=password
```

### Database Setup

```bash
# PostgreSQL with pgvector
psql -c "CREATE EXTENSION IF NOT EXISTS vector;"

# Run migrations
mix ecto.migrate
```

### Performance Tuning

```yaml
# High-throughput configuration
pipelines:
  ingestion:
    concurrency: 20
    batch_size: 100
  embedding:
    concurrency: 10
    rate_limit: 500

router:
  health_check_interval: 10000

adapters:
  vector_store:
    config:
      index_type: hnsw
      options:
        m: 32
        ef_construction: 128
```

---

## Next Steps

- [Gap Analysis](./gap-analysis.md) - Comparison with rag_ex features
- [Vision Document](./vision.md) - Ideal feature set roadmap
