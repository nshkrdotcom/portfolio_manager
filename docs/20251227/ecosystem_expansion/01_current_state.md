# Portfolio Manager - Current State Analysis

## Overview

**Version:** 0.2.0
**Role:** Application layer for the Portfolio ecosystem
**Dependencies:** portfolio_core (~0.1.1), portfolio_index (~0.1.1)

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    PORTFOLIO MANAGER                            │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │  CLI Layer (lib/mix/tasks/)                             │   │
│  │  • mix portfolio.ask    - RAG question answering        │   │
│  │  • mix portfolio.search - Semantic search               │   │
│  │  • mix portfolio.index  - Repository indexing           │   │
│  │  • mix portfolio.graph  - Graph operations              │   │
│  └─────────────────────────────────────────────────────────┘   │
│                              │                                  │
│  ┌───────────────────────────┴─────────────────────────────┐   │
│  │  Core Modules                                           │   │
│  │  • PortfolioManager.RAG   (~300 LOC) - RAG interface    │   │
│  │  • PortfolioManager.Graph (~145 LOC) - Graph ops        │   │
│  │  • PortfolioManager.Domain.Registry  - Session state    │   │
│  └─────────────────────────────────────────────────────────┘   │
│                              │                                  │
│  ┌───────────────────────────┴─────────────────────────────┐   │
│  │  Infrastructure                                         │   │
│  │  • Application     - OTP supervision tree               │   │
│  │  • Repo            - Ecto/PostgreSQL connection         │   │
│  │  • Manifest        - YAML config via portfolio_core     │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

## Implemented Features

### 1. RAG Module (`lib/portfolio_manager/rag.ex`)

| Function | Description | Status |
|----------|-------------|--------|
| `query/2` | Full RAG query with strategy selection | Complete |
| `ask/2` | Simplified interface (answer only) | Complete |
| `search/2` | Vector search without generation | Complete |
| `index_repo/2` | Index repository for RAG | Complete |

**Supported Strategies:**
- `:hybrid` - Vector + keyword with RRF fusion
- `:self_rag` - Self-assessment with critique
- `:graph_rag` - Graph-aware retrieval (stub in portfolio_index)
- `:agentic` - Agent-based retrieval (stub in portfolio_index)

### 2. Graph Module (`lib/portfolio_manager/graph.ex`)

| Function | Description | Status |
|----------|-------------|--------|
| `create_graph/2` | Create named graph | Complete |
| `add_node/2` | Add node with properties | Complete |
| `add_edge/2` | Add relationship | Complete |
| `neighbors/3` | Get adjacent nodes | Complete |
| `query/3` | Execute Cypher query | Complete |
| `stats/1` | Graph statistics | Complete |
| `build_dependency_graph/3` | Auto-build from repo | Complete |

**Dependency Extraction:**
- Elixir (mix.exs parsing)
- Python (requirements.txt parsing)

### 3. CLI Tools

| Task | Options | Description |
|------|---------|-------------|
| `portfolio.ask` | `--strategy`, `--top-k` | Ask questions via RAG |
| `portfolio.search` | `--limit`, `--filter` | Semantic search |
| `portfolio.index` | `--extensions`, `--ignore` | Index repositories |
| `portfolio.graph` | subcommands: `stats`, `build` | Graph management |

### 4. Configuration

**Manifest Location:** `config/manifests/{env}.yml`

```yaml
version: "1.0"
environment: development

adapters:
  vector_store:
    module: PortfolioIndex.Adapters.VectorStore.Pgvector
    config:
      dimensions: 768

  embedder:
    module: PortfolioIndex.Adapters.Embedder.Gemini
    config:
      model: text-embedding-004

  llm:
    module: PortfolioIndex.Adapters.LLM.Gemini
    config:
      model: gemini-2.0-flash-exp
```

## Current Gaps

### Missing from rag_ex

| Feature | rag_ex Status | portfolio_manager Status |
|---------|---------------|-------------------------|
| Multi-provider routing | 8 providers with strategies | Gemini only |
| Agent framework | Full tool-based agents | Not present |
| Pipeline orchestration | DAG with caching | Broadway via index |
| Streaming output | Supported | Not implemented |
| Multiple chunkers | 6 strategies | 1 (recursive) |
| Interactive mode | Not present | Not present |
| Full-text search | PostgreSQL tsvector | Via vector store only |

### Missing Generally

1. **HTTP API Layer** - Phoenix marked optional but not implemented
2. **WebSocket Support** - For streaming responses
3. **Multi-tenant Isolation** - Context available but not enforced
4. **Progress Reporting** - No feedback during long operations
5. **Configuration Validation** - Minimal manifest validation
6. **Caching Layer** - No query/embedding cache
7. **Rate Limiting** - Handled in portfolio_index but not exposed

## Code Metrics

| Metric | Value |
|--------|-------|
| Total LOC | ~953 |
| Main Modules | 4 |
| CLI Tasks | 4 |
| Test Files | ~6 |
| Examples | 5 |
| Guides | 5 |

## Dependencies

```elixir
# Core ecosystem
{:portfolio_core, "~> 0.1.1"}
{:portfolio_index, "~> 0.1.1"}

# Database
{:ecto_sql, "~> 3.11"}
{:postgrex, "~> 0.17"}

# CLI
{:optimus, "~> 0.5"}

# Web (optional, not used)
{:phoenix, "~> 1.7", optional: true}
{:phoenix_live_view, "~> 0.20", optional: true}
```

## Test Infrastructure

- **Framework:** ExUnit with Mox
- **Mocks:** All portfolio_core ports mocked
- **Coverage:** ExCoveralls configured
- **Fixtures:** Examples serve as integration tests

## Documentation

| Document | Purpose |
|----------|---------|
| `guides/getting_started.md` | Setup and first query |
| `guides/rag.md` | RAG query guide |
| `guides/graph.md` | Graph operations |
| `guides/configuration.md` | Manifest setup |
| `guides/cli.md` | CLI reference |
