# Portfolio Manager - Expansion Roadmap

## Overview

This document outlines the feature expansion plan for portfolio_manager, organized by priority tiers and implementation phases.

**Note:** This depends on portfolio_core v0.2.0 and portfolio_index v0.2.0.

## Priority Tiers

### Tier 1: Critical Path (Immediate Value)

#### 1.1 Multi-Provider LLM Support
**Goal:** Support multiple LLM providers with intelligent routing

```elixir
# Target API
PortfolioManager.RAG.query("What does this function do?",
  providers: [:gemini, :claude, :openai],
  routing: :fallback  # or :round_robin, :specialist
)
```

**Implementation:**
- Add router configuration to manifest
- Implement provider health checking
- Add cost tracking per provider
- Support provider-specific options

**Dependencies:** portfolio_index v0.2.0 LLM adapters (Anthropic via claude_agent_sdk, OpenAI via codex_sdk)

#### 1.2 Streaming Response Support
**Goal:** Stream LLM responses for better UX

```elixir
# Target API
PortfolioManager.RAG.stream_query("Explain this code", fn chunk ->
  IO.write(chunk)
end)

# CLI
mix portfolio.ask "question" --stream
```

**Implementation:**
- Add `stream/2` and `stream_query/2` to RAG module
- Update CLI tasks with streaming output
- Add progress indicators for indexing

**Dependencies:** portfolio_index LLM streaming

#### 1.3 Agent Framework
**Goal:** Enable tool-based reasoning for complex queries

```elixir
# Target API
PortfolioManager.Agent.run("Find all usages of this function and suggest improvements",
  tools: [:search_code, :read_file, :analyze_dependencies]
)
```

**Implementation:**
- Create `PortfolioManager.Agent` module
- Define tool behaviors and registry
- Implement core tools: search, read, graph traverse
- Add session memory for multi-turn

**Inspiration:** rag_ex agent framework

### Tier 2: Enhanced Functionality

#### 2.1 Phoenix HTTP API
**Goal:** REST and GraphQL APIs for web integration

```
POST /api/v1/query
POST /api/v1/search
POST /api/v1/index
GET  /api/v1/graphs/:id/stats
WS   /api/v1/stream
```

**Implementation:**
- Enable Phoenix dependency
- Create PortfolioManagerWeb context
- Implement REST controllers
- Add WebSocket for streaming
- Optional: GraphQL with Absinthe

#### 2.2 Advanced Chunking Strategies
**Goal:** Support multiple chunking approaches

```elixir
# Target manifest configuration
chunker:
  strategy: semantic  # character, sentence, paragraph, recursive, semantic
  config:
    max_size: 1000
    overlap: 100
    format_aware: true
```

**Implementation:**
- Port chunking strategies from rag_ex
- Add chunker behavior to portfolio_core
- Implement adapters in portfolio_index
- Update indexing to use configured chunker

#### 2.3 Pipeline Orchestration
**Goal:** Composable workflow pipelines with caching

```elixir
# Target API
PortfolioManager.Pipeline.run(:code_analysis, %{
  repo_path: "/path/to/repo"
}) do
  step :scan_files, &scan_repo/1
  step :extract_entities, &extract/1, depends_on: [:scan_files]
  step :build_graph, &graph/1, depends_on: [:extract_entities]
  step :generate_summary, &summarize/1, depends_on: [:build_graph]
end
```

**Implementation:**
- Create Pipeline module with DAG execution
- Add ETS-based step caching
- Implement parallel execution
- Add telemetry for pipeline events

**Inspiration:** rag_ex pipeline system

### Tier 3: Enterprise Features

#### 3.1 Multi-Tenant Support
**Goal:** Isolated tenant contexts with resource limits

```elixir
# Target API
PortfolioManager.with_tenant("tenant_123", fn ->
  PortfolioManager.RAG.query("question")
end)
```

**Implementation:**
- Add tenant context to all operations
- Implement tenant-scoped vector indexes
- Add tenant-scoped graph namespaces
- Resource quotas per tenant

#### 3.2 Caching Layer
**Goal:** Reduce API costs and latency

```elixir
# Target manifest configuration
cache:
  embeddings:
    backend: redis
    ttl: 86400
  queries:
    backend: ets
    ttl: 3600
  enabled: true
```

**Implementation:**
- Abstract cache port in portfolio_core
- Implement ETS and Redis adapters
- Cache embeddings by content hash
- Cache query results with invalidation

#### 3.3 Advanced Graph Operations
**Goal:** Graph analytics and federation

```elixir
# Target API
PortfolioManager.Graph.analyze(graph_id,
  algorithms: [:pagerank, :community_detection, :centrality]
)

PortfolioManager.Graph.federate([graph_1, graph_2],
  join_on: :shared_entities
)
```

**Implementation:**
- Add graph algorithm library
- Implement cross-graph queries
- Add graph versioning
- Support graph snapshots

## Implementation Phases

### Phase 1: Core Enhancements (Q1)
```
Week 1-2: Multi-provider support (manifest + routing)
Week 3-4: Streaming responses (LLM + CLI)
Week 5-6: Agent framework foundation
Week 7-8: Testing and documentation
```

### Phase 2: Web & Pipelines (Q2)
```
Week 1-4: Phoenix HTTP API
Week 5-6: Advanced chunking
Week 7-8: Pipeline orchestration
```

### Phase 3: Enterprise (Q3-Q4)
```
Month 1: Multi-tenant foundation
Month 2: Caching layer
Month 3: Advanced graph operations
```

## Success Metrics

| Feature | Metric | Target |
|---------|--------|--------|
| Multi-provider | Provider count | 4+ |
| Streaming | Time to first token | <500ms |
| Agent | Tool count | 10+ |
| HTTP API | Endpoints | 15+ |
| Chunking | Strategies | 5+ |
| Pipelines | Step types | 20+ |
| Multi-tenant | Isolation | 100% |
| Caching | Hit rate | >80% |

## Risk Mitigation

| Risk | Mitigation |
|------|------------|
| Breaking portfolio_core API | Version carefully, deprecation warnings |
| Performance regression | Benchmark before/after each phase |
| Complexity creep | Keep modules focused, refactor as needed |
| Dependency conflicts | Pin versions, test upgrade paths |
