# Arcana Feature Adoption Plan

**Date:** 2026-01-04
**Scope:** portfolio_core, portfolio_index, portfolio_manager
**Reference:** arcana/ (v1.2.0, 82 commits Dec 30 - Jan 4)

---

## Executive Summary

Arcana is a comprehensive RAG library with several production-ready features that the portfolio ecosystem lacks. This document outlines a technical implementation plan to adopt key Arcana features across the three portfolio repositories while respecting their hexagonal architecture.

---

## Feature Gap Analysis

### Features Arcana Has That Portfolio Repos Lack

| Feature | Arcana | portfolio_core | portfolio_index | portfolio_manager |
|---------|--------|----------------|-----------------|-------------------|
| LiveView Dashboard | Yes | N/A | No | No |
| Leiden Algorithm (theta param) | Yes | No | Partial | No |
| Graph Explorer UI | Yes | N/A | No | No |
| Orphaned Data Cleanup | Yes | No | No | No |
| TaskSupervisor for Async Ops | Yes | No | No | No |
| Local Embedder (Bumblebee) | Yes | Port exists | Partial | No |
| E5 Prefix Handling | Yes | No | No | No |
| HNSWLib In-Memory Store | Yes | No | No | No |
| mix rebuild_graph Task | Yes | No | No | No |
| mix detect_communities Task | Yes | No | No | No |
| Config Redaction | Yes | No | No | No |
| Per-Call Backend Override | Yes | No | No | No |
| Built-in Telemetry Logger | Yes | Basic | Basic | Basic |
| Community Detection Maintenance | Yes | No | Partial | No |
| Document Detail View | N/A (UI) | N/A | Schema exists | No |
| Collection Statistics | Yes | No | No | No |
| Graph-Enhanced Ingest Toggle | Yes | No | No | No |
| Resume/Skip for Re-embedding | Yes | No | No | No |

---

## Implementation Plan

### Phase 1: Core Infrastructure (portfolio_core)

#### 1.1 Add Leiden Theta Parameter to GraphStore.Community Port

**File:** `lib/portfolio_core/ports/graph_store/community.ex`

```elixir
@callback detect_communities(graph_id :: String.t(), opts :: keyword()) ::
            {:ok, [community()]} | {:error, term()}

# Add to opts documentation:
# - :resolution - float, default 1.0
# - :theta - float (0.0-1.0), default nil (for faster convergence)
# - :max_iterations - integer, default 100
```

**Rationale:** Arcana's Leiden implementation with theta parameter allows trading precision for speed in community detection.

---

#### 1.2 Add Config Redaction Utility

**File:** `lib/portfolio_core/config.ex` (new)

```elixir
defmodule PortfolioCore.Config do
  @sensitive_keys [:api_key, :secret, :password, :token, :credentials]

  @spec redact(map() | keyword()) :: map() | keyword()
  def redact(config) when is_map(config) do
    Map.new(config, fn {k, v} -> {k, maybe_redact(k, v)} end)
  end

  defp maybe_redact(key, value) when is_atom(key) do
    if key in @sensitive_keys, do: "[REDACTED]", else: deep_redact(value)
  end

  defp deep_redact(value) when is_map(value), do: redact(value)
  defp deep_redact(value) when is_list(value), do: Enum.map(value, &deep_redact/1)
  defp deep_redact(value), do: value
end
```

---

#### 1.3 Add Per-Call Backend Override Pattern

**File:** `lib/portfolio_core/ports/vector_store.ex`

Add documentation for `:backend_override` option pattern:

```elixir
# Options:
# - :backend_override - {module, config} tuple to use instead of registered adapter
```

This enables swapping backends per-operation (e.g., HNSWLib for tests, Pgvector for production).

---

#### 1.4 Enhanced Telemetry Logger

**File:** `lib/portfolio_core/telemetry/logger.ex` (new)

```elixir
defmodule PortfolioCore.Telemetry.Logger do
  require Logger

  @events [
    [:portfolio, :embedder, :embed, :stop],
    [:portfolio, :vector_store, :search, :stop],
    [:portfolio, :llm, :complete, :stop],
    [:portfolio, :rag, :pipeline, :stop],
    [:portfolio, :graph, :traverse, :stop],
    [:portfolio, :agent, :gate, :stop],
    [:portfolio, :agent, :reason, :stop]
  ]

  def attach do
    :telemetry.attach_many(
      "portfolio-core-logger",
      @events,
      &handle_event/4,
      nil
    )
  end

  def handle_event(event, measurements, metadata, _config) do
    Logger.info("[#{format_event(event)}] #{format_measurements(measurements)} #{format_metadata(metadata)}")
  end
end
```

---

### Phase 2: Adapter Layer (portfolio_index)

#### 2.1 HNSWLib In-Memory Vector Store Adapter

**File:** `lib/portfolio_index/adapters/vector_store/hnswlib.ex` (new)

```elixir
defmodule PortfolioIndex.Adapters.VectorStore.HNSWLib do
  @behaviour PortfolioCore.Ports.VectorStore

  # Dependency: {:hnswlib, "~> 0.1"}

  defstruct [:index, :id_map, :dimensions, :space]

  @impl true
  def search(config, _index_id, query_vector, k, opts \\ []) do
    # Use HNSWLib.Index.knn_query/3
  end

  @impl true
  def insert(config, _index_id, id, vector, _metadata) do
    # Use HNSWLib.Index.add_items/2
  end

  @impl true
  def delete(config, _index_id, id) do
    # Mark as deleted in id_map (HNSWLib doesn't support true deletion)
  end
end
```

**Use Case:** Fast unit tests without PostgreSQL, development environments.

---

#### 2.2 Enhanced Bumblebee Embedder with E5 Prefix Support

**File:** `lib/portfolio_index/adapters/embedder/bumblebee.ex`

Add E5 model detection and automatic prefix handling:

```elixir
defmodule PortfolioIndex.Adapters.Embedder.Bumblebee do
  @e5_models ["intfloat/e5-small", "intfloat/e5-base", "intfloat/e5-large",
              "intfloat/multilingual-e5-small", "intfloat/multilingual-e5-base"]

  def embed(config, text, opts \\ []) do
    model = Keyword.get(config, :model, "BAAI/bge-small-en-v1.5")
    text_type = Keyword.get(opts, :text_type, :query)

    prefixed_text = maybe_add_e5_prefix(model, text, text_type)
    do_embed(config, prefixed_text)
  end

  defp maybe_add_e5_prefix(model, text, type) when model in @e5_models do
    case type do
      :query -> "query: #{text}"
      :passage -> "passage: #{text}"
      _ -> text
    end
  end
  defp maybe_add_e5_prefix(_model, text, _type), do: text
end
```

**Supported Models to Add:**
- BGE: small, base, large (en-v1.5)
- E5: small, base, large, multilingual variants
- GTE: small, base, large
- MiniLM: L6-v2, L12-v2

---

#### 2.3 Leiden Theta Parameter in Community Detection

**File:** `lib/portfolio_index/graph_rag/community_detector.ex`

```elixir
def detect(graph_id, opts \\ []) do
  resolution = Keyword.get(opts, :resolution, 1.0)
  theta = Keyword.get(opts, :theta)  # nil = default precision, 0.0-1.0 = faster

  leiden_opts = [resolution: resolution]
  leiden_opts = if theta, do: [{:theta, theta} | leiden_opts], else: leiden_opts

  # Log execution parameters
  Logger.info("Leiden community detection: graph=#{graph_id}, resolution=#{resolution}, theta=#{inspect(theta)}")

  start_time = System.monotonic_time(:millisecond)
  result = ExLeiden.detect(graph, leiden_opts)
  duration = System.monotonic_time(:millisecond) - start_time

  Logger.info("Leiden completed: #{length(result)} communities in #{duration}ms")
  result
end
```

---

#### 2.4 Orphaned Data Management

**File:** `lib/portfolio_index/maintenance/orphan_cleanup.ex` (new)

```elixir
defmodule PortfolioIndex.Maintenance.OrphanCleanup do
  @moduledoc """
  Cleans up orphaned graph data (entities/relationships without parent documents).
  """

  alias PortfolioIndex.Repo

  def find_orphaned_entities(graph_id) do
    # Entities with no associated chunks/documents
  end

  def find_orphaned_relationships(graph_id) do
    # Relationships where source or target entity doesn't exist
  end

  def cleanup_orphaned_data(graph_id, opts \\ []) do
    dry_run = Keyword.get(opts, :dry_run, true)

    orphaned_entities = find_orphaned_entities(graph_id)
    orphaned_relationships = find_orphaned_relationships(graph_id)

    if dry_run do
      {:dry_run, %{entities: length(orphaned_entities), relationships: length(orphaned_relationships)}}
    else
      # Actually delete
    end
  end
end
```

---

#### 2.5 Enhanced Re-embedding with Resume/Skip

**File:** `lib/portfolio_index/maintenance/reembed.ex`

Add resume and skip capabilities:

```elixir
def reembed_chunks(opts \\ []) do
  collection_id = Keyword.get(opts, :collection_id)
  concurrency = Keyword.get(opts, :concurrency, 5)
  resume_from = Keyword.get(opts, :resume_from)  # chunk_id to resume from
  skip_embedded = Keyword.get(opts, :skip_embedded, false)
  progress_callback = Keyword.get(opts, :progress_callback)

  chunks = list_chunks_for_reembedding(collection_id, resume_from, skip_embedded)

  chunks
  |> Task.async_stream(&reembed_chunk/1, max_concurrency: concurrency)
  |> Stream.with_index()
  |> Enum.each(fn {{:ok, result}, idx} ->
    if progress_callback, do: progress_callback.(idx + 1, length(chunks), result)
  end)
end

defp list_chunks_for_reembedding(collection_id, resume_from, skip_embedded) do
  query = from(c in Chunk, order_by: c.id)

  query = if collection_id, do: where(query, [c], c.collection_id == ^collection_id), else: query
  query = if resume_from, do: where(query, [c], c.id > ^resume_from), else: query
  query = if skip_embedded, do: where(query, [c], is_nil(c.embedding)), else: query

  Repo.all(query)
end
```

---

#### 2.6 Collection Statistics

**File:** `lib/portfolio_index/vector_store/collections.ex`

```elixir
def get_statistics(collection_id) do
  %{
    document_count: count_documents(collection_id),
    chunk_count: count_chunks(collection_id),
    chunks_with_embeddings: count_chunks_with_embeddings(collection_id),
    chunks_without_embeddings: count_chunks_without_embeddings(collection_id),
    total_tokens: sum_tokens(collection_id),
    avg_chunk_size: avg_chunk_size(collection_id),
    entity_count: count_entities(collection_id),
    relationship_count: count_relationships(collection_id),
    community_count: count_communities(collection_id)
  }
end
```

---

### Phase 3: Application Layer (portfolio_manager)

#### 3.1 New Mix Tasks

**File:** `lib/mix/tasks/portfolio.rebuild_graph.ex` (new)

```elixir
defmodule Mix.Tasks.Portfolio.RebuildGraph do
  use Mix.Task

  @shortdoc "Rebuild knowledge graph from documents"

  def run(args) do
    {opts, _, _} = OptionParser.parse(args,
      switches: [collection: :string, force: :boolean])

    Mix.Task.run("app.start")

    collection_id = Keyword.get(opts, :collection)
    force = Keyword.get(opts, :force, false)

    IO.puts("Rebuilding graph#{if collection_id, do: " for collection #{collection_id}", else: ""}...")

    PortfolioManager.Graph.rebuild(collection_id: collection_id, force: force)
  end
end
```

**File:** `lib/mix/tasks/portfolio.detect_communities.ex` (new)

```elixir
defmodule Mix.Tasks.Portfolio.DetectCommunities do
  use Mix.Task

  @shortdoc "Detect communities in knowledge graph"

  def run(args) do
    {opts, _, _} = OptionParser.parse(args,
      switches: [graph: :string, resolution: :float, theta: :float, levels: :integer])

    Mix.Task.run("app.start")

    graph_id = Keyword.get(opts, :graph)
    resolution = Keyword.get(opts, :resolution, 1.0)
    theta = Keyword.get(opts, :theta)
    levels = Keyword.get(opts, :levels, 5)

    IO.puts("Detecting communities (resolution=#{resolution}, theta=#{inspect(theta)}, levels=#{levels})...")

    PortfolioManager.Graph.detect_communities(
      graph_id: graph_id,
      resolution: resolution,
      theta: theta,
      levels: levels
    )
  end
end
```

**File:** `lib/mix/tasks/portfolio.cleanup_orphans.ex` (new)

```elixir
defmodule Mix.Tasks.Portfolio.CleanupOrphans do
  use Mix.Task

  @shortdoc "Clean up orphaned graph data"

  def run(args) do
    {opts, _, _} = OptionParser.parse(args,
      switches: [graph: :string, dry_run: :boolean])

    Mix.Task.run("app.start")

    graph_id = Keyword.fetch!(opts, :graph)
    dry_run = Keyword.get(opts, :dry_run, true)

    IO.puts("#{if dry_run, do: "[DRY RUN] ", else: ""}Cleaning orphaned data for graph #{graph_id}...")

    PortfolioIndex.Maintenance.OrphanCleanup.cleanup_orphaned_data(graph_id, dry_run: dry_run)
  end
end
```

---

#### 3.2 TaskSupervisor for Async Operations

**File:** `lib/portfolio_manager/application.ex`

Add TaskSupervisor to supervision tree:

```elixir
def start(_type, _args) do
  children = [
    PortfolioManager.Repo,
    {Task.Supervisor, name: PortfolioManager.TaskSupervisor},  # Add this
    # ... other children
  ]

  opts = [strategy: :one_for_one, name: PortfolioManager.Supervisor]
  Supervisor.start_link(children, opts)
end
```

**File:** `lib/portfolio_manager/async.ex` (new)

```elixir
defmodule PortfolioManager.Async do
  @moduledoc """
  Utilities for supervised async operations.
  """

  require Logger

  def run(fun, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, :infinity)

    Task.Supervisor.async_nolink(
      PortfolioManager.TaskSupervisor,
      fn ->
        try do
          fun.()
        rescue
          e ->
            Logger.error("Async task failed: #{Exception.message(e)}\n#{Exception.format_stacktrace(__STACKTRACE__)}")
            {:error, e}
        end
      end
    )
    |> Task.yield(timeout)
    |> case do
      {:ok, result} -> result
      {:exit, reason} -> {:error, {:exit, reason}}
      nil -> {:error, :timeout}
    end
  end

  def run_async(fun) do
    Task.Supervisor.start_child(
      PortfolioManager.TaskSupervisor,
      fn ->
        try do
          fun.()
        rescue
          e ->
            Logger.error("Background task failed: #{Exception.message(e)}")
        end
      end
    )
  end
end
```

---

#### 3.3 Diagnostics Enhancement

**File:** `lib/mix/tasks/portfolio.diagnostics.ex`

Add collection statistics to diagnostics output:

```elixir
def run(_args) do
  Mix.Task.run("app.start")

  # Existing diagnostics...

  # Add collection statistics
  IO.puts("\n=== Collection Statistics ===")
  collections = PortfolioIndex.VectorStore.Collections.list()

  for collection <- collections do
    stats = PortfolioIndex.VectorStore.Collections.get_statistics(collection.id)
    IO.puts("Collection: #{collection.name}")
    IO.puts("  Documents: #{stats.document_count}")
    IO.puts("  Chunks: #{stats.chunk_count} (#{stats.chunks_with_embeddings} embedded)")
    IO.puts("  Entities: #{stats.entity_count}")
    IO.puts("  Relationships: #{stats.relationship_count}")
    IO.puts("  Communities: #{stats.community_count}")
    IO.puts("")
  end
end
```

---

### Phase 4: LiveView Dashboard (portfolio_manager)

This is the largest feature gap. Arcana provides a comprehensive LiveView dashboard that portfolio_manager lacks entirely.

#### 4.1 Dashboard Architecture

**New Directory Structure:**
```
lib/portfolio_manager_web/
├── router.ex
├── endpoint.ex
├── live/
│   ├── dashboard_live.ex
│   ├── documents_live.ex
│   ├── collections_live.ex
│   ├── search_live.ex
│   ├── ask_live.ex
│   ├── graph_live.ex
│   ├── evaluation_live.ex
│   ├── maintenance_live.ex
│   └── info_live.ex
├── components/
│   ├── layouts.ex
│   ├── core_components.ex
│   └── pagination_component.ex
└── templates/
```

**Dependencies to Add (mix.exs):**
```elixir
{:phoenix_live_view, "~> 1.0"},
{:phoenix_html, "~> 4.1"},
{:phoenix_live_reload, "~> 1.5", only: :dev},
{:tailwind, "~> 0.2", runtime: Mix.env() == :dev}
```

---

#### 4.2 Dashboard Pages

| Route | LiveView Module | Features |
|-------|-----------------|----------|
| `/portfolio` | DashboardLive | Overview, quick stats |
| `/portfolio/documents` | DocumentsLive | List, upload, view, delete documents |
| `/portfolio/collections` | CollectionsLive | CRUD, statistics per collection |
| `/portfolio/search` | SearchLive | Vector/hybrid search interface |
| `/portfolio/ask` | AskLive | Simple + agentic RAG Q&A |
| `/portfolio/graph` | GraphLive | Entity/relationship/community explorer with pagination |
| `/portfolio/evaluation` | EvaluationLive | Test case management, evaluation runs |
| `/portfolio/maintenance` | MaintenanceLive | Re-embed, rebuild graph, detect communities, cleanup |
| `/portfolio/info` | InfoLive | Configuration display (redacted), system info |

---

#### 4.3 Graph Explorer with Pagination (from Arcana)

**File:** `lib/portfolio_manager_web/live/graph_live.ex`

```elixir
defmodule PortfolioManagerWeb.GraphLive do
  use PortfolioManagerWeb, :live_view

  @per_page 50

  def mount(_params, _session, socket) do
    {:ok, assign(socket,
      active_tab: :entities,
      entity_page: 1,
      relationship_page: 1,
      community_page: 1,
      filter: "",
      graph_id: nil
    )}
  end

  def handle_event("select_tab", %{"tab" => tab}, socket) do
    {:noreply, assign(socket, active_tab: String.to_atom(tab))}
  end

  def handle_event("filter", %{"filter" => filter}, socket) do
    # Reset to page 1 on filter change
    {:noreply, assign(socket, filter: filter, entity_page: 1, relationship_page: 1, community_page: 1)}
  end

  def handle_event("page", %{"page" => page, "type" => type}, socket) do
    page_key = String.to_atom("#{type}_page")
    {:noreply, assign(socket, [{page_key, String.to_integer(page)}])}
  end

  defp list_entities(graph_id, filter, page) do
    PortfolioIndex.GraphRAG.list_entities(graph_id,
      filter: filter,
      limit: @per_page,
      offset: (page - 1) * @per_page
    )
  end
end
```

---

#### 4.4 Maintenance Page with Async Operations

**File:** `lib/portfolio_manager_web/live/maintenance_live.ex`

```elixir
defmodule PortfolioManagerWeb.MaintenanceLive do
  use PortfolioManagerWeb, :live_view

  def mount(_params, _session, socket) do
    {:ok, assign(socket,
      reembed_status: nil,
      rebuild_status: nil,
      community_status: nil,
      cleanup_status: nil,
      collections: list_collections()
    )}
  end

  def handle_event("reembed", %{"collection_id" => collection_id}, socket) do
    self_pid = self()

    Task.Supervisor.start_child(PortfolioManager.TaskSupervisor, fn ->
      PortfolioIndex.Maintenance.reembed_chunks(
        collection_id: collection_id,
        progress_callback: fn current, total, _result ->
          send(self_pid, {:reembed_progress, current, total})
        end
      )
      send(self_pid, :reembed_complete)
    end)

    {:noreply, assign(socket, reembed_status: %{current: 0, total: 0, status: :running})}
  end

  def handle_info({:reembed_progress, current, total}, socket) do
    {:noreply, assign(socket, reembed_status: %{current: current, total: total, status: :running})}
  end

  def handle_info(:reembed_complete, socket) do
    {:noreply, assign(socket, reembed_status: %{status: :complete})}
  end
end
```

---

## Implementation Priority

### High Priority (Immediate Value)

1. **Leiden Theta Parameter** - Easy win, improves community detection performance
2. **Enhanced Re-embedding** - Resume/skip capabilities for production robustness
3. **Orphaned Data Cleanup** - Data hygiene for long-running systems
4. **TaskSupervisor** - Better crash handling for async operations
5. **Collection Statistics** - Essential for monitoring

### Medium Priority (Feature Parity)

6. **HNSWLib Adapter** - Faster tests, offline development
7. **E5 Prefix Handling** - Better embedding model support
8. **New Mix Tasks** - rebuild_graph, detect_communities, cleanup_orphans
9. **Config Redaction** - Security for logging/display
10. **Enhanced Telemetry Logger** - Better observability

### Lower Priority (Nice to Have)

11. **LiveView Dashboard** - Significant effort, but high user value
12. **Graph Explorer** - Requires dashboard infrastructure
13. **Maintenance UI** - Requires dashboard infrastructure

---

## Dependency Changes

### portfolio_core/mix.exs
```elixir
# No new dependencies required
```

### portfolio_index/mix.exs
```elixir
# Add:
{:hnswlib, "~> 0.1", optional: true},
{:ex_leiden, "~> 0.5"}  # If not already present
```

### portfolio_manager/mix.exs
```elixir
# For dashboard (optional):
{:phoenix_live_view, "~> 1.0"},
{:phoenix_html, "~> 4.1"},
{:phoenix_live_reload, "~> 1.5", only: :dev},
{:tailwind, "~> 0.2", runtime: Mix.env() == :dev},
{:heroicons, "~> 0.5"}
```

---

## Testing Strategy

1. **Unit Tests** - Each new module with mocked dependencies
2. **Integration Tests** - HNSWLib adapter against in-memory store
3. **Property Tests** - Config redaction edge cases
4. **LiveView Tests** - If dashboard implemented

---

## Migration Notes

- No database migrations required for core features
- Dashboard would require Phoenix setup if not already present
- HNSWLib is optional dependency - code should handle missing dep gracefully

---

## Estimated Effort

| Phase | Components | Complexity |
|-------|------------|------------|
| Phase 1 | 4 components | Low |
| Phase 2 | 6 components | Medium |
| Phase 3 | 4 components | Medium |
| Phase 4 | Full dashboard | High |

---

## Conclusion

Arcana's recent development (82 commits in 5 days) has focused on production robustness: optimized algorithms, better async handling, comprehensive UI, and maintenance tools. The portfolio ecosystem would benefit most from adopting the infrastructure improvements (Phases 1-3) before considering the dashboard (Phase 4).

The hexagonal architecture of portfolio_core makes these additions straightforward - new capabilities fit cleanly into the existing port/adapter pattern without requiring architectural changes.
