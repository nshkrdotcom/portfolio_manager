# 09. Implementation Roadmap

## Strategic Overview

This roadmap outlines the phased implementation of the RAG ecosystem, transforming the current portfolio_manager into a multi-package architecture with a publishable hexagonal core on Hex.pm. The approach prioritizes incremental delivery, backward compatibility, and production stability.

---

## 1. Package Architecture Evolution

### Current State → Target State

```
CURRENT STATE                           TARGET STATE
─────────────────                       ─────────────────
portfolio_manager/                       portfolio_core/      (Hex.pm package)
├── lib/                                 ├── lib/portfolio_core/
│   ├── portfolio_manager/               │   ├── ports/       (Behavior contracts)
│   │   ├── adapters/                    │   ├── manifest/    (Config engine)
│   │   ├── domain/                      │   ├── registry/    (Adapter registry)
│   │   ├── graph.ex                     │   └── wiring/      (DI framework)
│   │   ├── rag.ex                       │
│   │   └── workflow/                    portfolio_index/     (Private package)
│   └── mix/tasks/                       ├── lib/portfolio_index/
└── config/                              │   ├── adapters/    (Vector, Graph, Doc)
                                         │   ├── pipelines/   (Broadway pipelines)
                                         │   └── rag/         (RAG implementations)
                                         │
                                         portfolio_manager/   (Application)
                                         ├── lib/
                                         │   ├── cli/         (Mix tasks)
                                         │   └── web/         (Phoenix API)
                                         └── config/          (Manifests)
```

---

## 2. Implementation Phases

### Phase 0: Foundation (Weeks 1-2)

**Objective**: Establish development infrastructure and patterns.

#### Deliverables

```elixir
# 1. Create umbrella project structure
mix new portfolio_ecosystem --umbrella

# 2. Initialize sub-applications
cd apps
mix new portfolio_core --module PortfolioCore
mix new portfolio_index --module PortfolioIndex
# Move existing code to portfolio_manager app
```

#### Tasks

| Task | Priority | Dependencies |
|------|----------|--------------|
| Create umbrella project structure | Critical | None |
| Set up CI/CD pipeline for multi-package | Critical | Umbrella |
| Configure shared test helpers | High | Umbrella |
| Set up code coverage thresholds | Medium | CI/CD |
| Create architecture decision records (ADRs) | Medium | None |
| Document coding standards | Medium | None |

#### Milestone Criteria
- [ ] Umbrella project compiles
- [ ] Existing tests pass in portfolio_manager app
- [ ] CI/CD runs for all apps
- [ ] Coverage reporting works

---

### Phase 1: Port Extraction (Weeks 3-5)

**Objective**: Extract port behaviors to portfolio_core.

#### Port Extraction Order

```
Week 3: Foundation Ports
├── PortfolioCore.Storage.Port          (base storage behavior)
├── PortfolioCore.Cache.Port            (caching abstraction)
└── PortfolioCore.Telemetry.Port        (observability)

Week 4: Data Ports
├── PortfolioCore.VectorStore.Port      (embedding storage)
├── PortfolioCore.GraphStore.Port       (knowledge graphs)
├── PortfolioCore.DocumentStore.Port    (document storage)
└── PortfolioCore.ChunkStore.Port       (chunk management)

Week 5: Intelligence Ports
├── PortfolioCore.Embedder.Port         (embedding generation)
├── PortfolioCore.LLM.Port              (language model access)
├── PortfolioCore.Retriever.Port        (retrieval strategies)
└── PortfolioCore.Reranker.Port         (result reranking)
```

#### Example: Port Extraction Pattern

```elixir
# Step 1: Define port in portfolio_core
# apps/portfolio_core/lib/portfolio_core/ports/vector_store.ex
defmodule PortfolioCore.Ports.VectorStore do
  @moduledoc """
  Port specification for vector storage backends.
  """

  @type index_id :: String.t()
  @type vector :: [float()]
  @type metadata :: map()
  @type search_result :: %{id: String.t(), score: float(), metadata: metadata()}

  @callback store(index_id(), id :: String.t(), vector(), metadata()) ::
    :ok | {:error, term()}

  @callback search(index_id(), vector(), k :: pos_integer(), opts :: keyword()) ::
    {:ok, [search_result()]} | {:error, term()}

  @callback delete(index_id(), id :: String.t()) :: :ok | {:error, term()}

  @callback create_index(index_id(), config :: map()) :: :ok | {:error, term()}

  @callback index_stats(index_id()) ::
    {:ok, %{count: non_neg_integer(), dimensions: pos_integer()}} | {:error, term()}
end

# Step 2: Create stub adapter in portfolio_index
# apps/portfolio_index/lib/portfolio_index/adapters/vector_store/pgvector.ex
defmodule PortfolioIndex.Adapters.VectorStore.Pgvector do
  @behaviour PortfolioCore.Ports.VectorStore

  # Move implementation from portfolio_manager
  @impl true
  def store(index_id, id, vector, metadata) do
    # Existing implementation
  end
end

# Step 3: Update portfolio_manager to use port
# apps/portfolio_manager/lib/portfolio_manager/rag.ex
defmodule PortfolioManager.RAG do
  alias PortfolioCore.Ports.VectorStore

  def search(query, opts) do
    adapter = PortfolioCore.Registry.get(:vector_store)
    VectorStore.search(adapter, opts[:index], query_vector, opts[:k])
  end
end
```

#### Milestone Criteria
- [ ] All ports defined with @callback specs
- [ ] Each port has at least one adapter
- [ ] Existing functionality unchanged
- [ ] Port documentation complete

---

### Phase 2: Manifest Engine (Weeks 6-8)

**Objective**: Implement manifest-based configuration system.

#### Manifest Schema Definition

```yaml
# config/manifests/development.yml
version: "1.0"
environment: development

adapters:
  vector_store:
    adapter: PortfolioIndex.Adapters.VectorStore.Pgvector
    config:
      repo: PortfolioManager.Repo
      table: embeddings
      index_method: ivfflat

  graph_store:
    adapter: PortfolioIndex.Adapters.GraphStore.Neo4j
    config:
      uri: ${NEO4J_URI}
      database: development
      pool_size: 5

  embedder:
    adapter: PortfolioIndex.Adapters.Embedder.OpenAI
    config:
      model: text-embedding-3-small
      dimensions: 1536
      api_key: ${OPENAI_API_KEY}
      rate_limit:
        requests_per_minute: 3000
        tokens_per_minute: 1_000_000

  llm:
    adapter: PortfolioIndex.Adapters.LLM.Anthropic
    config:
      model: claude-3-sonnet
      api_key: ${ANTHROPIC_API_KEY}
      max_tokens: 4096

pipelines:
  ingestion:
    adapter: PortfolioIndex.Pipelines.Ingestion
    config:
      batch_size: 50
      concurrency: 10
      rate_limit: 100/minute

  embedding:
    adapter: PortfolioIndex.Pipelines.Embedding
    config:
      batch_size: 100
      max_concurrency: 5

graphs:
  default:
    id: default
    type: knowledge
    config:
      community_detection: true
      entity_resolution: true

  dependencies:
    id: dependencies
    type: dependency
    config:
      languages: [elixir, python, javascript]
```

#### Manifest Engine Implementation

```elixir
# apps/portfolio_core/lib/portfolio_core/manifest/engine.ex
defmodule PortfolioCore.Manifest.Engine do
  @moduledoc """
  Loads and validates manifests, wires adapters to ports.
  """

  use GenServer
  require Logger

  defstruct [:manifest_path, :adapters, :config, :validated_at]

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Load manifest and wire all adapters.
  """
  def load_manifest(path) do
    GenServer.call(__MODULE__, {:load, path})
  end

  @doc """
  Get adapter instance for a port.
  """
  def get_adapter(port_name) do
    GenServer.call(__MODULE__, {:get_adapter, port_name})
  end

  @doc """
  Reload manifest (hot reload in dev).
  """
  def reload do
    GenServer.call(__MODULE__, :reload)
  end

  @impl true
  def init(opts) do
    path = opts[:manifest_path] || default_manifest_path()

    case load_and_validate(path) do
      {:ok, manifest} ->
        adapters = wire_adapters(manifest)
        {:ok, %__MODULE__{manifest_path: path, adapters: adapters, config: manifest}}

      {:error, reason} ->
        {:stop, {:manifest_error, reason}}
    end
  end

  @impl true
  def handle_call({:load, path}, _from, state) do
    case load_and_validate(path) do
      {:ok, manifest} ->
        adapters = wire_adapters(manifest)
        new_state = %{state | manifest_path: path, adapters: adapters, config: manifest}
        {:reply, :ok, new_state}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:get_adapter, port_name}, _from, state) do
    adapter = Map.get(state.adapters, port_name)
    {:reply, adapter, state}
  end

  defp load_and_validate(path) do
    with {:ok, content} <- File.read(path),
         {:ok, yaml} <- YamlElixir.read_from_string(content),
         {:ok, manifest} <- expand_env_vars(yaml),
         :ok <- validate_schema(manifest) do
      {:ok, manifest}
    end
  end

  defp expand_env_vars(config) when is_map(config) do
    expanded = Enum.map(config, fn {k, v} ->
      {:ok, expanded_v} = expand_env_vars(v)
      {k, expanded_v}
    end)
    {:ok, Map.new(expanded)}
  end

  defp expand_env_vars(value) when is_binary(value) do
    expanded = Regex.replace(~r/\$\{(\w+)\}/, value, fn _, var_name ->
      System.get_env(var_name) || raise "Missing env var: #{var_name}"
    end)
    {:ok, expanded}
  end

  defp expand_env_vars(value), do: {:ok, value}

  defp wire_adapters(manifest) do
    for {port_name, config} <- manifest["adapters"], into: %{} do
      adapter_module = String.to_existing_atom("Elixir." <> config["adapter"])
      adapter_config = config["config"] || %{}

      # Start adapter process if it's a GenServer
      adapter = start_adapter(adapter_module, adapter_config)

      {String.to_atom(port_name), adapter}
    end
  end

  defp start_adapter(module, config) do
    if function_exported?(module, :start_link, 1) do
      {:ok, pid} = DynamicSupervisor.start_child(
        PortfolioCore.AdapterSupervisor,
        {module, config}
      )
      pid
    else
      # Stateless adapter - just return module
      {module, config}
    end
  end
end
```

#### Milestone Criteria
- [ ] Manifest schema documented with JSON Schema
- [ ] Environment variable expansion works
- [ ] Hot reload in development
- [ ] Validation errors are descriptive
- [ ] All adapters wire correctly

---

### Phase 3: Adapter Migration (Weeks 9-12)

**Objective**: Migrate existing adapters to portfolio_index.

#### Adapter Migration Matrix

| Adapter | Source Location | Target Location | Status |
|---------|-----------------|-----------------|--------|
| LocalGit | portfolio_manager/adapters | portfolio_index/adapters/git | Planned |
| YamlStorage | portfolio_manager/adapters | portfolio_index/adapters/storage | Planned |
| FileDetector | portfolio_manager/adapters | portfolio_index/adapters/detection | Planned |
| SQLite Cache | portfolio_manager/cache | portfolio_index/adapters/cache | Planned |
| Pgvector | (new) | portfolio_index/adapters/vector | Planned |
| Neo4j | (new) | portfolio_index/adapters/graph | Planned |
| Qdrant | (new) | portfolio_index/adapters/vector | Planned |
| OpenAI Embedder | (new) | portfolio_index/adapters/embedder | Planned |
| Anthropic LLM | (new) | portfolio_index/adapters/llm | Planned |

#### Migration Pattern

```elixir
# Step 1: Create adapter in portfolio_index (following port contract)
defmodule PortfolioIndex.Adapters.GraphStore.Neo4j do
  @behaviour PortfolioCore.Ports.GraphStore
  use GenServer

  # Implementation...
end

# Step 2: Add to manifest
# config/manifests/production.yml
adapters:
  graph_store:
    adapter: PortfolioIndex.Adapters.GraphStore.Neo4j
    config:
      uri: ${NEO4J_URI}
      username: ${NEO4J_USER}
      password: ${NEO4J_PASSWORD}

# Step 3: Update calling code in portfolio_manager
defmodule PortfolioManager.Graph do
  alias PortfolioCore.Manifest.Engine

  def add_node(graph_id, node) do
    adapter = Engine.get_adapter(:graph_store)
    PortfolioCore.Ports.GraphStore.create_node(adapter, graph_id, node)
  end
end

# Step 4: Remove old implementation from portfolio_manager
# (After all references updated)
```

#### Milestone Criteria
- [ ] All adapters implement port behaviors
- [ ] Old adapter code removed from portfolio_manager
- [ ] Tests pass with new adapter locations
- [ ] No circular dependencies between packages

---

### Phase 4: Pipeline System (Weeks 13-16)

**Objective**: Implement Broadway-based ingestion pipelines.

#### Pipeline Architecture

```
                                    ┌─────────────────────────────────────┐
                                    │          Pipeline Registry          │
                                    │  ┌─────────────────────────────────┐│
                                    │  │ ingestion → IngestionPipeline   ││
                                    │  │ embedding → EmbeddingPipeline   ││
                                    │  │ indexing  → IndexingPipeline    ││
                                    │  └─────────────────────────────────┘│
                                    └─────────────────────────────────────┘
                                                      │
          ┌───────────────────────────────────────────┼───────────────────────────────────────────┐
          │                                           │                                           │
          ▼                                           ▼                                           ▼
┌──────────────────────┐                   ┌──────────────────────┐                   ┌──────────────────────┐
│  Ingestion Pipeline  │                   │  Embedding Pipeline  │                   │   Indexing Pipeline  │
│  ┌────────────────┐  │                   │  ┌────────────────┐  │                   │  ┌────────────────┐  │
│  │   Producer     │  │                   │  │   Producer     │  │                   │  │   Producer     │  │
│  │  (File/Git)    │  │                   │  │ (Chunk Queue)  │  │                   │  │ (Embed Queue)  │  │
│  └───────┬────────┘  │                   │  └───────┬────────┘  │                   │  └───────┬────────┘  │
│          │           │                   │          │           │                   │          │           │
│  ┌───────▼────────┐  │                   │  ┌───────▼────────┐  │                   │  ┌───────▼────────┐  │
│  │  Processor 1   │  │                   │  │  Rate Limiter  │  │                   │  │  Vector Store  │  │
│  │  (Parse/Chunk) │  │─────Queue───────▶│  │  (Token Count) │  │─────Queue───────▶│  │   (Upsert)     │  │
│  └───────┬────────┘  │                   │  └───────┬────────┘  │                   │  └───────┬────────┘  │
│          │           │                   │          │           │                   │          │           │
│  ┌───────▼────────┐  │                   │  ┌───────▼────────┐  │                   │  ┌───────▼────────┐  │
│  │  Processor 2   │  │                   │  │  Embedder API  │  │                   │  │  Graph Store   │  │
│  │  (Metadata)    │  │                   │  │  (Batch Call)  │  │                   │  │   (Upsert)     │  │
│  └───────┬────────┘  │                   │  └───────┬────────┘  │                   │  └───────┬────────┘  │
│          │           │                   │          │           │                   │          │           │
│  ┌───────▼────────┐  │                   │  ┌───────▼────────┐  │                   │  ┌───────▼────────┐  │
│  │   Batcher      │  │                   │  │   Batcher      │  │                   │  │   Batcher      │  │
│  │   (50 docs)    │  │                   │  │   (100 emb)    │  │                   │  │   (100 items)  │  │
│  └────────────────┘  │                   │  └────────────────┘  │                   │  └────────────────┘  │
└──────────────────────┘                   └──────────────────────┘                   └──────────────────────┘
```

#### Pipeline Implementation

```elixir
# apps/portfolio_index/lib/portfolio_index/pipelines/ingestion.ex
defmodule PortfolioIndex.Pipelines.Ingestion do
  use Broadway
  require Logger

  alias PortfolioCore.Telemetry

  def start_link(opts) do
    Broadway.start_link(__MODULE__,
      name: opts[:name] || __MODULE__,
      producer: [
        module: {PortfolioIndex.Pipelines.Producers.FileProducer, opts[:producer_config]},
        transformer: {__MODULE__, :transform, []},
        concurrency: opts[:producer_concurrency] || 1
      ],
      processors: [
        default: [
          concurrency: opts[:processor_concurrency] || 10,
          min_demand: 5,
          max_demand: 10
        ]
      ],
      batchers: [
        chunk_queue: [
          concurrency: 2,
          batch_size: opts[:batch_size] || 50,
          batch_timeout: 1000
        ]
      ]
    )
  end

  def transform(event, _opts) do
    %Broadway.Message{
      data: event,
      acknowledger: {__MODULE__, :ack_id, :ack_data}
    }
  end

  @impl true
  def handle_message(_, message, _) do
    Telemetry.with_span "pipeline.ingestion.process", %{file: message.data.path} do
      case process_file(message.data) do
        {:ok, chunks} ->
          message
          |> Broadway.Message.update_data(fn _ -> chunks end)
          |> Broadway.Message.put_batcher(:chunk_queue)

        {:error, reason} ->
          Broadway.Message.failed(message, reason)
      end
    end
  end

  @impl true
  def handle_batch(:chunk_queue, messages, _batch_info, _context) do
    chunks = Enum.flat_map(messages, & &1.data)

    # Send to embedding queue
    for chunk <- chunks do
      PortfolioIndex.Pipelines.Embedding.enqueue(chunk)
    end

    Logger.info("Batched #{length(chunks)} chunks for embedding")
    messages
  end

  defp process_file(%{path: path, type: type}) do
    with {:ok, content} <- File.read(path),
         {:ok, parsed} <- parse_content(content, type),
         {:ok, chunks} <- chunk_content(parsed) do
      {:ok, chunks}
    end
  end

  defp parse_content(content, :markdown), do: {:ok, %{text: content, format: :markdown}}
  defp parse_content(content, :elixir), do: parse_elixir(content)
  defp parse_content(content, _), do: {:ok, %{text: content, format: :plain}}

  defp chunk_content(parsed) do
    chunker = PortfolioCore.Manifest.Engine.get_adapter(:chunker)
    PortfolioCore.Ports.Chunker.chunk(chunker, parsed.text, parsed.format)
  end
end
```

#### Milestone Criteria
- [ ] All pipelines use Broadway
- [ ] Rate limiting prevents API overload
- [ ] Backpressure works end-to-end
- [ ] Failed messages route to DLQ
- [ ] Telemetry covers all stages

---

### Phase 5: RAG Strategies (Weeks 17-20)

**Objective**: Implement advanced RAG patterns.

#### RAG Strategy Registry

```elixir
# apps/portfolio_index/lib/portfolio_index/rag/registry.ex
defmodule PortfolioIndex.RAG.Registry do
  @moduledoc """
  Registry of RAG strategies with dynamic selection.
  """

  @strategies %{
    naive: PortfolioIndex.RAG.Strategies.Naive,
    self_rag: PortfolioIndex.RAG.Strategies.SelfRAG,
    crag: PortfolioIndex.RAG.Strategies.CRAG,
    graph_rag: PortfolioIndex.RAG.Strategies.GraphRAG,
    agentic: PortfolioIndex.RAG.Strategies.Agentic,
    multi_hop: PortfolioIndex.RAG.Strategies.MultiHop,
    hybrid: PortfolioIndex.RAG.Strategies.Hybrid
  }

  def get_strategy(name) when is_atom(name) do
    Map.get(@strategies, name) || {:error, :unknown_strategy}
  end

  def available_strategies, do: Map.keys(@strategies)

  @doc """
  Auto-select strategy based on query characteristics.
  """
  def auto_select(query, context \\ %{}) do
    cond do
      complex_reasoning_required?(query) -> :agentic
      requires_graph_context?(query, context) -> :graph_rag
      multi_step_query?(query) -> :multi_hop
      needs_verification?(context) -> :self_rag
      true -> :hybrid
    end
  end

  defp complex_reasoning_required?(query) do
    # Detect queries requiring multi-step reasoning
    patterns = [
      ~r/compare.*and/i,
      ~r/what are the differences/i,
      ~r/how does.*relate to/i,
      ~r/analyze.*impact/i
    ]
    Enum.any?(patterns, &Regex.match?(&1, query))
  end

  defp requires_graph_context?(query, context) do
    Map.get(context, :has_graph, false) and
    (query =~ ~r/relationship|connected|depends on|used by/i)
  end

  defp multi_step_query?(query) do
    query =~ ~r/first.*then|step by step|how to/i
  end

  defp needs_verification?(context) do
    Map.get(context, :high_stakes, false)
  end
end
```

#### Strategy Implementations

| Strategy | Implementation | Use Case |
|----------|----------------|----------|
| Naive | Vector search + LLM | Simple Q&A |
| Self-RAG | Retrieval + Self-critique | Accuracy-critical |
| CRAG | Corrective retrieval | Uncertain contexts |
| GraphRAG | Graph + Vector hybrid | Relationship queries |
| Agentic | Tool-using agent | Complex tasks |
| Multi-hop | Iterative retrieval | Multi-step reasoning |
| Hybrid | Ensemble methods | General purpose |

#### Milestone Criteria
- [ ] All strategies implement common interface
- [ ] Strategy selection is configurable
- [ ] Performance benchmarks documented
- [ ] Cost tracking per strategy
- [ ] Fallback behavior defined

---

### Phase 6: Multi-Graph System (Weeks 21-24)

**Objective**: Implement graph federation with graph-of-graphs.

#### Graph Hierarchy

```
                        ┌─────────────────────────────────────┐
                        │         Meta-Graph (Root)           │
                        │  ┌─────────────────────────────────┐│
                        │  │ Indexes all graph metadata      ││
                        │  │ Routes cross-graph queries      ││
                        │  │ Manages graph lifecycle         ││
                        │  └─────────────────────────────────┘│
                        └─────────────────────────────────────┘
                                          │
                    ┌─────────────────────┼─────────────────────┐
                    │                     │                     │
                    ▼                     ▼                     ▼
        ┌───────────────────┐ ┌───────────────────┐ ┌───────────────────┐
        │   Domain Graph A  │ │   Domain Graph B  │ │   Domain Graph C  │
        │  (Knowledge Base) │ │   (Code Base)     │ │  (Dependencies)   │
        │                   │ │                   │ │                   │
        │  - Entities       │ │  - Modules        │ │  - Packages       │
        │  - Relationships  │ │  - Functions      │ │  - Versions       │
        │  - Properties     │ │  - Calls          │ │  - Conflicts      │
        └───────────────────┘ └───────────────────┘ └───────────────────┘
                    │                     │                     │
                    └─────────────────────┼─────────────────────┘
                                          │
                                          ▼
                        ┌─────────────────────────────────────┐
                        │       Cross-Graph Connections       │
                        │  ┌─────────────────────────────────┐│
                        │  │ Code → Knowledge references     ││
                        │  │ Dependency → Code usage         ││
                        │  │ Knowledge → Dependency impact   ││
                        │  └─────────────────────────────────┘│
                        └─────────────────────────────────────┘
```

#### Implementation

```elixir
# apps/portfolio_index/lib/portfolio_index/graph/federation.ex
defmodule PortfolioIndex.Graph.Federation do
  @moduledoc """
  Federated graph queries across multiple graph instances.
  """

  alias PortfolioCore.Manifest.Engine

  @doc """
  Execute query across multiple graphs.
  """
  def federated_query(query, graph_ids, opts \\ []) do
    # Get adapters for each graph
    results = graph_ids
    |> Task.async_stream(fn graph_id ->
      adapter = get_graph_adapter(graph_id)
      {graph_id, execute_on_graph(adapter, graph_id, query, opts)}
    end, max_concurrency: opts[:max_concurrency] || 10)
    |> Enum.reduce(%{}, fn {:ok, {graph_id, result}}, acc ->
      Map.put(acc, graph_id, result)
    end)

    # Merge results
    merge_strategy = opts[:merge] || :union
    merge_results(results, merge_strategy)
  end

  @doc """
  Query across graph boundary via meta-graph.
  """
  def cross_graph_query(query, opts \\ []) do
    meta_adapter = get_graph_adapter(:meta)

    # First, query meta-graph to find relevant graphs
    relevant = find_relevant_graphs(meta_adapter, query)

    # Then, execute on relevant graphs
    federated_query(query, relevant, opts)
  end

  @doc """
  Create a cross-graph edge.
  """
  def create_cross_edge(from_graph, from_node, to_graph, to_node, edge_type, props \\ %{}) do
    meta_adapter = get_graph_adapter(:meta)

    # Record in meta-graph
    edge = %{
      from_graph: from_graph,
      from_node: from_node,
      to_graph: to_graph,
      to_node: to_node,
      type: edge_type,
      properties: props
    }

    PortfolioCore.Ports.GraphStore.create_edge(meta_adapter, :meta, edge)
  end

  defp get_graph_adapter(graph_id) do
    # Each graph may have different adapter configuration
    config = Engine.get_adapter(:graph_store)
    {adapter_module, adapter_config} = config

    # Override database for specific graph
    graph_config = get_graph_config(graph_id)
    merged_config = Map.merge(adapter_config, graph_config)

    {adapter_module, merged_config}
  end

  defp merge_results(results, :union) do
    Enum.reduce(results, %{nodes: [], edges: []}, fn {_, result}, acc ->
      %{
        nodes: acc.nodes ++ result.nodes,
        edges: acc.edges ++ result.edges
      }
    end)
  end

  defp merge_results(results, :intersection) do
    # Only include nodes present in all graphs
    all_node_ids = results
    |> Map.values()
    |> Enum.map(fn r -> MapSet.new(Enum.map(r.nodes, & &1.id)) end)
    |> Enum.reduce(&MapSet.intersection/2)

    %{
      nodes: Enum.filter(hd(Map.values(results)).nodes, &(&1.id in all_node_ids)),
      edges: []
    }
  end
end
```

#### Milestone Criteria
- [ ] Meta-graph routes queries correctly
- [ ] Cross-graph edges persist properly
- [ ] Federated queries aggregate results
- [ ] Graph lifecycle managed via meta-graph
- [ ] Performance acceptable for 10+ graphs

---

### Phase 7: Hex.pm Package (Weeks 25-28)

**Objective**: Prepare portfolio_core for public release.

#### Package Preparation Checklist

```markdown
## Code Quality
- [ ] All public functions have @doc
- [ ] All modules have @moduledoc
- [ ] Type specs (@spec) for public API
- [ ] No compiler warnings
- [ ] Credo passes with strict config
- [ ] Dialyzer passes

## Documentation
- [ ] README.md with quick start
- [ ] CHANGELOG.md following Keep a Changelog
- [ ] LICENSE file (MIT recommended)
- [ ] Guides in docs/ folder
- [ ] ExDoc configured with groups

## Testing
- [ ] >90% test coverage
- [ ] Property-based tests for core logic
- [ ] Integration tests with mock adapters
- [ ] CI runs on multiple Elixir/OTP versions

## API Stability
- [ ] No breaking changes without semver major bump
- [ ] Deprecated functions marked with @deprecated
- [ ] Behavior callbacks use optional callbacks where appropriate
- [ ] Configuration uses compile-time defaults with runtime overrides

## Package Config
- [ ] mix.exs has correct metadata
- [ ] Dependencies are minimal
- [ ] No dev-only deps leak to production
```

#### mix.exs for Hex.pm

```elixir
# apps/portfolio_core/mix.exs
defmodule PortfolioCore.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/your-org/portfolio_core"

  def project do
    [
      app: :portfolio_core,
      version: @version,
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: description(),
      package: package(),
      docs: docs(),
      name: "PortfolioCore",
      source_url: @source_url,
      homepage_url: "https://hexdocs.pm/portfolio_core",
      dialyzer: [
        plt_file: {:no_warn, "priv/plts/dialyzer.plt"},
        flags: [:error_handling, :unknown]
      ]
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {PortfolioCore.Application, []}
    ]
  end

  defp deps do
    [
      # Core dependencies (minimal)
      {:yaml_elixir, "~> 2.9"},
      {:jason, "~> 1.4"},
      {:telemetry, "~> 1.2"},

      # Dev/test only
      {:ex_doc, "~> 0.31", only: :dev, runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:stream_data, "~> 0.6", only: [:dev, :test]},
      {:mox, "~> 1.1", only: :test}
    ]
  end

  defp description do
    """
    Hexagonal architecture core for building flexible RAG systems.
    Provides port specifications, manifest-based configuration, and adapter wiring.
    """
  end

  defp package do
    [
      name: "portfolio_core",
      licenses: ["MIT"],
      links: %{
        "GitHub" => @source_url,
        "Docs" => "https://hexdocs.pm/portfolio_core"
      },
      maintainers: ["Your Name"],
      files: ~w(lib .formatter.exs mix.exs README.md LICENSE CHANGELOG.md)
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: [
        "README.md",
        "CHANGELOG.md",
        "docs/guides/getting-started.md",
        "docs/guides/writing-adapters.md",
        "docs/guides/manifest-configuration.md"
      ],
      groups_for_modules: [
        "Ports": ~r/PortfolioCore\.Ports\./,
        "Manifest": ~r/PortfolioCore\.Manifest\./,
        "Registry": ~r/PortfolioCore\.Registry\./
      ]
    ]
  end
end
```

#### Milestone Criteria
- [ ] Package publishes to Hex.pm
- [ ] Documentation renders on HexDocs
- [ ] At least 3 example adapters work
- [ ] No breaking API issues in first week
- [ ] GitHub stars > 50 in first month (aspirational)

---

### Phase 8: Production Hardening (Weeks 29-32)

**Objective**: Prepare for production deployment.

#### Production Readiness Checklist

```markdown
## Performance
- [ ] Load testing completed (target: 1000 req/s)
- [ ] Memory profiling done, no leaks
- [ ] Query performance benchmarked
- [ ] Index rebuild time acceptable
- [ ] Embedding batch size optimized

## Reliability
- [ ] Circuit breakers on all external calls
- [ ] Retry policies with exponential backoff
- [ ] Graceful degradation paths defined
- [ ] Health checks implemented
- [ ] Liveness/readiness probes work

## Security
- [ ] Security audit completed
- [ ] Penetration testing done
- [ ] All secrets in Vault/KMS
- [ ] API authentication enforced
- [ ] Rate limiting configured

## Observability
- [ ] Dashboards created (Grafana)
- [ ] Alerting rules deployed
- [ ] Log aggregation working
- [ ] Distributed tracing functional
- [ ] Error tracking (Sentry) integrated

## Operations
- [ ] Runbooks documented
- [ ] Incident response plan
- [ ] Backup/restore tested
- [ ] Disaster recovery plan
- [ ] On-call rotation established

## Compliance
- [ ] Data classification applied
- [ ] Retention policies automated
- [ ] Audit logging verified
- [ ] GDPR compliance tested
- [ ] SOC 2 controls documented
```

---

## 3. Risk Mitigation

### Technical Risks

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| Breaking changes during extraction | Medium | High | Feature flags, parallel implementations |
| Performance regression | Medium | Medium | Continuous benchmarking, rollback plan |
| Adapter incompatibility | Low | Medium | Comprehensive test suite per adapter |
| Manifest complexity | Medium | Low | Schema validation, migration tools |
| Neo4j scalability limits | Low | High | Sharding strategy, read replicas |
| Embedding API rate limits | High | Medium | Rate limiter, queue-based batching |
| Memory pressure from vectors | Medium | High | Streaming, pagination, index partitioning |

### Organizational Risks

| Risk | Probability | Impact | Mitigation |
|------|-------------|--------|------------|
| Scope creep | High | Medium | Strict phase gates, MVP focus |
| Key person dependency | Medium | High | Documentation, pair programming |
| Underestimated complexity | Medium | High | Spike tasks, prototype phases |
| External dependency changes | Low | Medium | Abstraction layers, version pinning |

---

## 4. Success Metrics

### Phase Completion Criteria

| Phase | Key Metric | Target |
|-------|------------|--------|
| 0: Foundation | CI/CD green | 100% |
| 1: Ports | Port coverage | 100% of adapters |
| 2: Manifest | Config files migrated | 100% |
| 3: Adapters | Tests passing | 100% |
| 4: Pipelines | Throughput | 1000 docs/min |
| 5: RAG | Query accuracy | >85% |
| 6: Multi-Graph | Federation latency | <100ms |
| 7: Hex.pm | Download count | >100/week |
| 8: Production | Uptime | 99.9% |

### Long-term Success Indicators

- **Adoption**: Community contributions, GitHub stars, Hex.pm downloads
- **Reliability**: Uptime, mean time to recovery, incident count
- **Performance**: Query latency p95, embedding throughput
- **Efficiency**: LLM cost per query, infrastructure cost trend
- **Velocity**: Time to add new adapter, time to deploy changes

---

## 5. Team & Resource Allocation

### Recommended Team Structure

```
Project Lead (1)
├── Core Platform (2)
│   ├── Port specifications
│   ├── Manifest engine
│   └── Hex.pm package
├── Data Engineering (2)
│   ├── Vector adapters
│   ├── Graph adapters
│   └── Storage optimization
├── ML/RAG (1-2)
│   ├── RAG strategies
│   ├── Embedding pipelines
│   └── Performance tuning
├── Infrastructure (1)
│   ├── CI/CD
│   ├── Observability
│   └── Security
└── QA/Documentation (1)
    ├── Test automation
    ├── API documentation
    └── User guides
```

---

## 6. Timeline Summary

```
2024
────────────────────────────────────────────────────────────────────────────────
Q1                    │ Q2                    │ Q3                    │ Q4
──────────────────────┼───────────────────────┼───────────────────────┼─────────
Phase 0-1             │ Phase 2-3             │ Phase 4-5             │ Phase 6-7
Foundation & Ports    │ Manifest & Adapters   │ Pipelines & RAG       │ Multi-Graph & Hex
                      │                       │                       │
Deliverables:         │ Deliverables:         │ Deliverables:         │ Deliverables:
• Umbrella structure  │ • Manifest engine     │ • Broadway pipelines  │ • Graph federation
• Port behaviors      │ • Adapter migration   │ • RAG strategies      │ • portfolio_core 0.1
• CI/CD pipeline      │ • Configuration docs  │ • Cost tracking       │ • Documentation

2025 Q1
────────────────────────────────────────────────────────────────────────────────
Phase 8: Production Hardening
• Performance optimization
• Security hardening
• Operational readiness
• GA release
```

---

## 7. Getting Started

### Immediate Next Steps

1. **Create umbrella project structure**
   ```bash
   mix new portfolio_ecosystem --umbrella
   cd portfolio_ecosystem/apps
   mix new portfolio_core --module PortfolioCore
   mix new portfolio_index --module PortfolioIndex
   # Move existing portfolio_manager code
   ```

2. **Define first port (VectorStore)**
   - Create behavior specification
   - Write comprehensive documentation
   - Implement test helpers

3. **Set up CI/CD**
   - Multi-app test runner
   - Coverage thresholds
   - Credo/Dialyzer checks

4. **Write Architecture Decision Records**
   - ADR-001: Umbrella vs Monorepo
   - ADR-002: Port specification patterns
   - ADR-003: Manifest schema design

---

This roadmap provides a comprehensive path from the current portfolio_manager to a production-ready, multi-package RAG ecosystem. Each phase builds on the previous, with clear milestones and risk mitigation strategies. The hexagonal architecture ensures long-term maintainability while the manifest system provides the flexibility needed for diverse deployment scenarios.
