# Hexagonal Core Design: Manifest-Based Ports and Adapters

**Expert:** Prof. Marcus Chen, Senior Fellow Software Architect
**Experience:** Amazon, Netflix, Enterprise Architecture Consulting

---

## Table of Contents

1. [Pure Hexagonal Principles](#pure-hexagonal-principles)
2. [Port Specifications](#port-specifications)
3. [Adapter Patterns](#adapter-patterns)
4. [Manifest Engine Design](#manifest-engine-design)
5. [Domain Model Purity](#domain-model-purity)
6. [Publishing portfolio_core to Hex](#publishing-portfolio_core-to-hex)
7. [Complete Port Behavior Definitions](#complete-port-behavior-definitions)

---

## 1. Pure Hexagonal Principles

### 1.1 The Hexagonal Promise

The hexagonal architecture (ports and adapters) makes one fundamental promise:
**The domain core has ZERO dependencies on infrastructure.**

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         OUTSIDE WORLD                                    │
│  ┌────────────┐  ┌────────────┐  ┌────────────┐  ┌────────────┐        │
│  │   CLI      │  │  HTTP API  │  │  GraphQL   │  │  Workflow  │        │
│  │  Adapter   │  │  Adapter   │  │  Adapter   │  │  Engine    │        │
│  └─────┬──────┘  └─────┬──────┘  └─────┬──────┘  └─────┬──────┘        │
│        │               │               │               │                │
│        └───────────────┴───────────────┴───────────────┘                │
│                                │                                         │
│                    ┌───────────▼───────────┐                            │
│                    │    PRIMARY PORTS      │                            │
│                    │  (Driving the core)   │                            │
│                    └───────────┬───────────┘                            │
│  ┌──────────────────────────────────────────────────────────────────┐  │
│  │                      DOMAIN CORE                                  │  │
│  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐            │  │
│  │  │   Entities   │  │   Services   │  │    Events    │            │  │
│  │  │              │  │              │  │              │            │  │
│  │  │  Repository  │  │  Ingestion   │  │  GraphUpdated│            │  │
│  │  │  Document    │  │  Retrieval   │  │  ChunkStored │            │  │
│  │  │  Chunk       │  │  GraphQuery  │  │  QueryExec   │            │  │
│  │  │  Entity      │  │              │  │              │            │  │
│  │  │  Edge        │  │              │  │              │            │  │
│  │  └──────────────┘  └──────────────┘  └──────────────┘            │  │
│  │                                                                   │  │
│  │  ╔══════════════════════════════════════════════════════════════╗│  │
│  │  ║                    MANIFEST ENGINE                           ║│  │
│  │  ║  Port Resolution │ Adapter Wiring │ Config Overlay          ║│  │
│  │  ╚══════════════════════════════════════════════════════════════╝│  │
│  └──────────────────────────────────────────────────────────────────┘  │
│                    ┌───────────┴───────────┐                            │
│                    │   SECONDARY PORTS     │                            │
│                    │  (Driven by core)     │                            │
│                    └───────────┬───────────┘                            │
│        ┌───────────────────────┼───────────────────────┐                │
│        │           │           │           │           │                │
│  ┌─────▼────┐ ┌────▼────┐ ┌────▼────┐ ┌────▼────┐ ┌────▼────┐          │
│  │ pgvector │ │  Neo4j  │ │ Qdrant  │ │ Gemini  │ │ RocksDB │          │
│  │ Adapter  │ │ Adapter │ │ Adapter │ │ Adapter │ │ Adapter │          │
│  └──────────┘ └─────────┘ └─────────┘ └─────────┘ └─────────┘          │
└─────────────────────────────────────────────────────────────────────────┘
```

### 1.2 Dependency Rule

The fundamental rule: **Dependencies point inward.**

```elixir
# ❌ WRONG: Core depends on adapter
defmodule PortfolioCore.Domain.IngestionService do
  alias PortfolioIndex.Adapters.Pgvector  # VIOLATION!

  def ingest(doc) do
    Pgvector.store(doc)  # Direct adapter call
  end
end

# ✅ CORRECT: Core depends only on port (behavior)
defmodule PortfolioCore.Domain.IngestionService do
  @callback store_chunk(chunk :: Chunk.t()) :: {:ok, id} | {:error, reason}

  def ingest(doc, vector_store) do
    # vector_store implements VectorStorePort behavior
    vector_store.store_chunk(doc)
  end
end
```

### 1.3 Port Types

**Primary Ports (Driving):** How the outside world interacts with the core
- `CommandPort` - Mutations (ingest, update, delete)
- `QueryPort` - Read operations (search, retrieve)
- `EventPort` - Event subscriptions

**Secondary Ports (Driven):** How the core interacts with infrastructure
- `VectorStorePort` - Vector storage and search
- `GraphStorePort` - Graph storage and traversal
- `EmbedderPort` - Embedding generation
- `ChunkerPort` - Content chunking
- `DocumentStorePort` - Document persistence
- `AuditPort` - Audit logging

---

## 2. Port Specifications

### 2.1 VectorStorePort

```elixir
defmodule PortfolioCore.Ports.VectorStorePort do
  @moduledoc """
  Port for vector storage and similarity search operations.

  Adapters must implement all callbacks. The port supports:
  - Multiple indexes with different embedding models
  - Batch operations for efficient ingestion
  - Filtered search with metadata predicates
  - Hybrid search combining dense and sparse vectors
  """

  @type index_id :: atom() | String.t()
  @type chunk_id :: String.t()
  @type embedding :: [float()]
  @type metadata :: map()
  @type filter :: keyword() | map()

  @type chunk :: %{
    id: chunk_id(),
    content: String.t(),
    embedding: embedding(),
    metadata: metadata()
  }

  @type search_result :: %{
    chunk_id: chunk_id(),
    score: float(),
    content: String.t(),
    metadata: metadata()
  }

  @type search_opts :: [
    index_id: index_id(),
    limit: pos_integer(),
    filter: filter(),
    min_score: float(),
    include_vectors: boolean()
  ]

  # Lifecycle
  @callback init(config :: map()) :: {:ok, state :: term()} | {:error, reason :: term()}
  @callback health_check(state :: term()) :: :ok | {:error, reason :: term()}

  # Index Management
  @callback create_index(index_id(), dimensions :: pos_integer(), opts :: keyword()) ::
    {:ok, index_id()} | {:error, reason :: term()}
  @callback delete_index(index_id()) :: :ok | {:error, reason :: term()}
  @callback list_indexes() :: {:ok, [index_id()]} | {:error, reason :: term()}

  # CRUD Operations
  @callback store_chunk(chunk()) :: {:ok, chunk_id()} | {:error, reason :: term()}
  @callback store_chunks(chunks :: [chunk()]) :: {:ok, [chunk_id()]} | {:error, reason :: term()}
  @callback get_chunk(chunk_id()) :: {:ok, chunk()} | {:error, :not_found}
  @callback delete_chunk(chunk_id()) :: :ok | {:error, reason :: term()}
  @callback delete_chunks(chunk_ids :: [chunk_id()]) :: :ok | {:error, reason :: term()}

  # Search Operations
  @callback search(embedding(), search_opts()) :: {:ok, [search_result()]} | {:error, reason :: term()}
  @callback search_hybrid(query :: String.t(), embedding(), search_opts()) ::
    {:ok, [search_result()]} | {:error, reason :: term()}

  # Batch Operations
  @callback upsert_batch(chunks :: [chunk()], opts :: keyword()) ::
    {:ok, stats :: map()} | {:error, reason :: term()}

  # Metadata
  @callback count(index_id(), filter()) :: {:ok, non_neg_integer()} | {:error, reason :: term()}
  @callback get_index_info(index_id()) :: {:ok, map()} | {:error, reason :: term()}

  # Optional callbacks for advanced features
  @optional_callbacks [search_hybrid: 3, get_index_info: 1]
end
```

### 2.2 GraphStorePort

```elixir
defmodule PortfolioCore.Ports.GraphStorePort do
  @moduledoc """
  Port for graph storage, traversal, and community detection.

  Supports multi-graph architectures where each graph_id represents
  an isolated namespace (per-repo, per-domain, or meta-graph).
  """

  @type graph_id :: atom() | String.t()
  @type entity_id :: String.t()
  @type edge_id :: String.t()
  @type community_id :: String.t()

  @type entity :: %{
    id: entity_id(),
    graph_id: graph_id(),
    type: String.t(),
    name: String.t(),
    properties: map(),
    embedding: [float()] | nil,
    source_chunk_ids: [String.t()]
  }

  @type edge :: %{
    id: edge_id(),
    graph_id: graph_id(),
    from_id: entity_id(),
    to_id: entity_id(),
    type: String.t(),
    weight: float(),
    properties: map()
  }

  @type community :: %{
    id: community_id(),
    graph_id: graph_id(),
    level: non_neg_integer(),
    summary: String.t(),
    entity_ids: [entity_id()]
  }

  @type traversal_opts :: [
    depth: pos_integer(),
    edge_types: [String.t()],
    direction: :outgoing | :incoming | :both,
    limit: pos_integer()
  ]

  # Lifecycle
  @callback init(config :: map()) :: {:ok, state :: term()} | {:error, reason :: term()}
  @callback health_check() :: :ok | {:error, reason :: term()}

  # Graph Management
  @callback create_graph(graph_id(), opts :: keyword()) :: {:ok, graph_id()} | {:error, term()}
  @callback delete_graph(graph_id()) :: :ok | {:error, term()}
  @callback list_graphs() :: {:ok, [graph_id()]} | {:error, term()}

  # Entity Operations
  @callback insert_entity(entity()) :: {:ok, entity_id()} | {:error, term()}
  @callback insert_entities(entities :: [entity()]) :: {:ok, [entity_id()]} | {:error, term()}
  @callback get_entity(graph_id(), entity_id()) :: {:ok, entity()} | {:error, :not_found}
  @callback update_entity(entity()) :: {:ok, entity()} | {:error, term()}
  @callback delete_entity(graph_id(), entity_id()) :: :ok | {:error, term()}

  # Edge Operations
  @callback insert_edge(edge()) :: {:ok, edge_id()} | {:error, term()}
  @callback insert_edges(edges :: [edge()]) :: {:ok, [edge_id()]} | {:error, term()}
  @callback get_edge(graph_id(), edge_id()) :: {:ok, edge()} | {:error, :not_found}
  @callback delete_edge(graph_id(), edge_id()) :: :ok | {:error, term()}

  # Traversal
  @callback traverse(graph_id(), entity_id(), traversal_opts()) ::
    {:ok, [entity()]} | {:error, term()}
  @callback shortest_path(graph_id(), entity_id(), entity_id()) ::
    {:ok, [entity()]} | {:error, :no_path}
  @callback neighbors(graph_id(), entity_id(), opts :: keyword()) ::
    {:ok, [entity()]} | {:error, term()}

  # Search
  @callback search_entities(graph_id(), query :: map()) ::
    {:ok, [entity()]} | {:error, term()}
  @callback search_by_embedding(graph_id(), embedding :: [float()], opts :: keyword()) ::
    {:ok, [entity()]} | {:error, term()}

  # Community Detection
  @callback detect_communities(graph_id(), algorithm :: atom(), opts :: keyword()) ::
    {:ok, [community()]} | {:error, term()}
  @callback get_community(graph_id(), community_id()) ::
    {:ok, community()} | {:error, :not_found}
  @callback get_communities(graph_id(), level :: non_neg_integer()) ::
    {:ok, [community()]} | {:error, term()}

  # Cross-Graph Operations (for graph-of-graphs)
  @callback create_cross_graph_edge(from_graph :: graph_id(), from_entity :: entity_id(),
                                     to_graph :: graph_id(), to_entity :: entity_id(),
                                     edge_type :: String.t()) ::
    {:ok, edge_id()} | {:error, term()}
  @callback traverse_cross_graph(start_graph :: graph_id(), entity_id(), opts :: keyword()) ::
    {:ok, [%{graph_id: graph_id(), entity: entity()}]} | {:error, term()}

  @optional_callbacks [
    detect_communities: 3,
    create_cross_graph_edge: 5,
    traverse_cross_graph: 3
  ]
end
```

### 2.3 EmbedderPort

```elixir
defmodule PortfolioCore.Ports.EmbedderPort do
  @moduledoc """
  Port for generating embeddings from text content.

  Supports multiple embedding models with different dimensions
  and characteristics. Adapters handle batching and rate limiting.
  """

  @type model_id :: atom() | String.t()
  @type embedding :: [float()]
  @type content :: String.t()

  @type embed_opts :: [
    model: model_id(),
    normalize: boolean(),
    truncate: boolean()
  ]

  @type model_info :: %{
    id: model_id(),
    dimensions: pos_integer(),
    max_tokens: pos_integer(),
    supports_batch: boolean()
  }

  # Lifecycle
  @callback init(config :: map()) :: {:ok, state :: term()} | {:error, term()}
  @callback health_check() :: :ok | {:error, term()}

  # Embedding Operations
  @callback embed(content(), embed_opts()) :: {:ok, embedding()} | {:error, term()}
  @callback embed_batch(contents :: [content()], embed_opts()) ::
    {:ok, [embedding()]} | {:error, term()}

  # Model Information
  @callback list_models() :: {:ok, [model_info()]} | {:error, term()}
  @callback get_model_info(model_id()) :: {:ok, model_info()} | {:error, :not_found}
  @callback dimensions(model_id()) :: {:ok, pos_integer()} | {:error, term()}

  # Cost Tracking
  @callback estimate_cost(contents :: [content()], model_id()) ::
    {:ok, %{tokens: integer(), cost_usd: float()}} | {:error, term()}
end
```

### 2.4 ChunkerPort

```elixir
defmodule PortfolioCore.Ports.ChunkerPort do
  @moduledoc """
  Port for splitting documents into chunks for embedding.

  Supports multiple chunking strategies including character-based,
  sentence-based, semantic, and code-aware chunking.
  """

  @type strategy :: :character | :sentence | :paragraph | :recursive | :semantic | :code
  @type chunk :: %{
    content: String.t(),
    index: non_neg_integer(),
    start_offset: non_neg_integer(),
    end_offset: non_neg_integer(),
    metadata: map()
  }

  @type chunk_opts :: [
    strategy: strategy(),
    chunk_size: pos_integer(),
    chunk_overlap: non_neg_integer(),
    separators: [String.t()],
    language: atom()  # For code chunking
  ]

  # Chunking Operations
  @callback chunk(content :: String.t(), opts :: chunk_opts()) ::
    {:ok, [chunk()]} | {:error, term()}

  @callback chunk_document(document :: map(), opts :: chunk_opts()) ::
    {:ok, [chunk()]} | {:error, term()}

  # Strategy Information
  @callback list_strategies() :: [strategy()]
  @callback strategy_info(strategy()) :: {:ok, map()} | {:error, :not_found}

  # Estimation
  @callback estimate_chunks(content :: String.t(), opts :: chunk_opts()) ::
    {:ok, non_neg_integer()} | {:error, term()}
end
```

### 2.5 DocumentStorePort

```elixir
defmodule PortfolioCore.Ports.DocumentStorePort do
  @moduledoc """
  Port for document storage with content-addressable features.
  """

  @type doc_id :: String.t()
  @type content_hash :: String.t()

  @type document :: %{
    id: doc_id(),
    path: String.t(),
    content: String.t(),
    content_hash: content_hash(),
    repo_id: String.t(),
    metadata: map(),
    created_at: DateTime.t(),
    updated_at: DateTime.t()
  }

  # CRUD
  @callback store(document()) :: {:ok, doc_id()} | {:error, term()}
  @callback get(doc_id()) :: {:ok, document()} | {:error, :not_found}
  @callback get_by_hash(content_hash()) :: {:ok, document()} | {:error, :not_found}
  @callback delete(doc_id()) :: :ok | {:error, term()}

  # Query
  @callback list_by_repo(repo_id :: String.t()) :: {:ok, [document()]} | {:error, term()}
  @callback list_by_path(path_pattern :: String.t()) :: {:ok, [document()]} | {:error, term()}

  # Versioning
  @callback get_versions(doc_id()) :: {:ok, [document()]} | {:error, term()}
  @callback get_version(doc_id(), version :: pos_integer()) :: {:ok, document()} | {:error, term()}
end
```

### 2.6 AuditPort

```elixir
defmodule PortfolioCore.Ports.AuditPort do
  @moduledoc """
  Port for audit logging and provenance tracking.
  """

  @type audit_event :: %{
    id: String.t(),
    timestamp: DateTime.t(),
    action: atom(),
    actor: String.t(),
    resource_type: atom(),
    resource_id: String.t(),
    details: map(),
    trace_id: String.t() | nil
  }

  @callback log(audit_event()) :: :ok | {:error, term()}
  @callback log_batch(events :: [audit_event()]) :: :ok | {:error, term()}

  @callback query(filters :: keyword()) :: {:ok, [audit_event()]} | {:error, term()}
  @callback get_lineage(resource_type :: atom(), resource_id :: String.t()) ::
    {:ok, [audit_event()]} | {:error, term()}
end
```

---

## 3. Adapter Patterns

### 3.1 Base Adapter Behavior

```elixir
defmodule PortfolioIndex.Adapter do
  @moduledoc """
  Base behavior for all adapters.
  Provides common functionality and registration.
  """

  @callback port() :: module()
  @callback capabilities() :: [atom()]
  @callback config_schema() :: map()

  defmacro __using__(opts) do
    port = Keyword.fetch!(opts, :port)

    quote do
      @behaviour unquote(port)
      @behaviour PortfolioIndex.Adapter

      @impl PortfolioIndex.Adapter
      def port, do: unquote(port)

      # Default implementations
      @impl PortfolioIndex.Adapter
      def capabilities, do: []

      @impl PortfolioIndex.Adapter
      def config_schema, do: %{}

      defoverridable capabilities: 0, config_schema: 0
    end
  end
end
```

### 3.2 Concrete Adapter Example: Pgvector

```elixir
defmodule PortfolioIndex.Adapters.Pgvector do
  @moduledoc """
  Vector store adapter using PostgreSQL with pgvector extension.
  """

  use PortfolioIndex.Adapter, port: PortfolioCore.Ports.VectorStorePort
  use GenServer

  alias PortfolioIndex.Schema.VectorChunk

  defstruct [:repo, :default_index, :config]

  @impl PortfolioIndex.Adapter
  def capabilities do
    [:search, :batch_upsert, :filtered_search, :hybrid_search]
  end

  @impl PortfolioIndex.Adapter
  def config_schema do
    %{
      repo: [type: :atom, required: true],
      default_index: [type: :string, default: "default"],
      pool_size: [type: :integer, default: 10]
    }
  end

  # GenServer lifecycle
  def start_link(opts) do
    config = Keyword.fetch!(opts, :config)
    name = Keyword.get(opts, :name)
    GenServer.start_link(__MODULE__, config, name: name)
  end

  @impl GenServer
  def init(config) do
    state = %__MODULE__{
      repo: config[:repo],
      default_index: config[:default_index] || "default",
      config: config
    }
    {:ok, state}
  end

  # VectorStorePort implementation
  @impl PortfolioCore.Ports.VectorStorePort
  def init(config) do
    {:ok, %{repo: config[:repo]}}
  end

  @impl PortfolioCore.Ports.VectorStorePort
  def health_check(_state) do
    case Ecto.Adapters.SQL.query(repo(), "SELECT 1", []) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @impl PortfolioCore.Ports.VectorStorePort
  def store_chunk(chunk) do
    %VectorChunk{}
    |> VectorChunk.changeset(chunk)
    |> repo().insert()
    |> case do
      {:ok, record} -> {:ok, record.id}
      {:error, changeset} -> {:error, changeset}
    end
  end

  @impl PortfolioCore.Ports.VectorStorePort
  def store_chunks(chunks) do
    repo().insert_all(VectorChunk, chunks, returning: [:id])
    |> case do
      {count, records} -> {:ok, Enum.map(records, & &1.id)}
    end
  end

  @impl PortfolioCore.Ports.VectorStorePort
  def search(embedding, opts) do
    index_id = Keyword.get(opts, :index_id, "default")
    limit = Keyword.get(opts, :limit, 10)
    filter = Keyword.get(opts, :filter, %{})

    query = build_search_query(embedding, index_id, limit, filter)

    case repo().all(query) do
      results -> {:ok, format_results(results)}
    end
  end

  defp build_search_query(embedding, index_id, limit, filter) do
    import Ecto.Query

    base = from(c in VectorChunk,
      where: c.index_id == ^index_id,
      order_by: fragment("embedding <-> ?", ^embedding),
      limit: ^limit,
      select: %{
        chunk_id: c.id,
        content: c.content,
        score: fragment("1 - (embedding <-> ?)", ^embedding),
        metadata: c.metadata
      }
    )

    Enum.reduce(filter, base, fn
      {:repo_id, value}, q -> where(q, [c], c.metadata["repo_id"] == ^value)
      {:path, pattern}, q -> where(q, [c], like(c.metadata["path"], ^pattern))
      _, q -> q
    end)
  end

  defp repo, do: Application.get_env(:portfolio_index, :repo)
  defp format_results(results), do: results
end
```

### 3.3 Adapter Decorator Pattern

```elixir
defmodule PortfolioIndex.Adapters.Decorators.Cached do
  @moduledoc """
  Caching decorator that wraps any VectorStorePort adapter.
  """

  defstruct [:inner_adapter, :cache, :ttl]

  def wrap(adapter, cache_module, opts \\ []) do
    %__MODULE__{
      inner_adapter: adapter,
      cache: cache_module,
      ttl: Keyword.get(opts, :ttl, 3600_000)
    }
  end

  def search(%__MODULE__{} = decorated, embedding, opts) do
    cache_key = :erlang.phash2({embedding, opts})

    case decorated.cache.get(:search, cache_key) do
      {:ok, cached} ->
        {:ok, cached}

      {:error, :not_found} ->
        case decorated.inner_adapter.search(embedding, opts) do
          {:ok, results} = success ->
            decorated.cache.put(:search, cache_key, results, decorated.ttl)
            success

          error ->
            error
        end
    end
  end

  # Delegate other calls to inner adapter
  def store_chunk(%__MODULE__{} = decorated, chunk) do
    decorated.inner_adapter.store_chunk(chunk)
  end

  def store_chunks(%__MODULE__{} = decorated, chunks) do
    decorated.inner_adapter.store_chunks(chunks)
  end
end
```

### 3.4 Adapter Decorator: Metrics

```elixir
defmodule PortfolioIndex.Adapters.Decorators.Instrumented do
  @moduledoc """
  Telemetry decorator for any adapter.
  """

  defstruct [:inner_adapter, :prefix]

  def wrap(adapter, prefix) do
    %__MODULE__{inner_adapter: adapter, prefix: prefix}
  end

  def search(%__MODULE__{} = decorated, embedding, opts) do
    metadata = %{adapter: decorated.inner_adapter.__struct__, opts: opts}

    :telemetry.span(
      [decorated.prefix, :search],
      metadata,
      fn ->
        result = decorated.inner_adapter.search(embedding, opts)
        {result, Map.put(metadata, :result_count, result_count(result))}
      end
    )
  end

  defp result_count({:ok, results}), do: length(results)
  defp result_count(_), do: 0
end
```

---

## 4. Manifest Engine Design

### 4.1 Manifest Schema

```yaml
# config/manifests/production.yaml
version: 2
environment: production
inherit: base.yaml

ports:
  vector_store:
    adapter: portfolio_index.adapters.qdrant
    decorators:
      - type: cached
        config:
          ttl: 3600000
      - type: instrumented
        config:
          prefix: portfolio.vector
    config:
      url: ${QDRANT_URL}
      api_key: ${QDRANT_API_KEY}
      collection_prefix: prod_

  graph_store:
    adapter: portfolio_index.adapters.neo4j
    config:
      uri: ${NEO4J_URI}
      username: ${NEO4J_USER}
      password: ${NEO4J_PASSWORD}
      database: production
      pool_size: 50

  embedder:
    adapter: portfolio_index.adapters.gemini
    config:
      model: text-embedding-004
      api_key: ${GEMINI_API_KEY}
      rate_limit: 100
      rate_window_ms: 60000

  chunker:
    adapter: portfolio_index.adapters.recursive_chunker
    config:
      chunk_size: 1000
      chunk_overlap: 200

pipelines:
  ingest:
    concurrency: 4
    steps:
      - name: discover
        type: file_discovery
      - name: chunk
        type: chunking
        uses_port: chunker
      - name: embed
        type: embedding
        uses_port: embedder
        batch_size: 50
      - name: store_vectors
        type: vector_storage
        uses_port: vector_store
      - name: extract_entities
        type: entity_extraction
      - name: store_graph
        type: graph_storage
        uses_port: graph_store

  query:
    steps:
      - name: embed_query
        type: embedding
        uses_port: embedder
      - name: retrieve
        type: retrieval
        uses_port: vector_store
        config:
          limit: 20
      - name: graph_expand
        type: graph_expansion
        uses_port: graph_store
        config:
          depth: 2
      - name: rerank
        type: reranking
      - name: synthesize
        type: generation

feature_flags:
  graph_rag_enabled: true
  hybrid_search: true
  community_detection: false

indexes:
  code_dense:
    adapter: portfolio_index.adapters.qdrant
    embedding_model: code-embedder-v2
    dimensions: 1536
  docs_dense:
    adapter: portfolio_index.adapters.pgvector
    embedding_model: text-embedding-004
    dimensions: 768

graphs:
  default:
    adapter: portfolio_index.adapters.neo4j
    database: default
  meta:
    adapter: portfolio_index.adapters.neo4j
    database: meta_graph
```

### 4.2 Manifest Parser

```elixir
defmodule PortfolioCore.Manifest.Parser do
  @moduledoc """
  Parses and validates manifest YAML files.
  """

  @spec parse!(path :: String.t()) :: map() | no_return()
  def parse!(path) do
    path
    |> File.read!()
    |> YamlElixir.read_from_string!()
    |> resolve_env_vars()
    |> resolve_inheritance()
    |> validate!()
    |> atomize_keys()
  end

  defp resolve_env_vars(manifest) do
    deep_transform(manifest, fn
      "${" <> rest ->
        var_name = String.trim_trailing(rest, "}")
        System.get_env(var_name) || raise "Missing env var: #{var_name}"

      other ->
        other
    end)
  end

  defp resolve_inheritance(%{"inherit" => parent_path} = manifest) do
    parent = parse!(parent_path)
    deep_merge(parent, Map.delete(manifest, "inherit"))
  end

  defp resolve_inheritance(manifest), do: manifest

  defp validate!(manifest) do
    schema = PortfolioCore.Manifest.Schema.v2()

    case NimbleOptions.validate(manifest, schema) do
      {:ok, validated} -> validated
      {:error, error} -> raise "Invalid manifest: #{inspect(error)}"
    end
  end

  defp deep_transform(map, fun) when is_map(map) do
    Map.new(map, fn {k, v} -> {k, deep_transform(v, fun)} end)
  end

  defp deep_transform(list, fun) when is_list(list) do
    Enum.map(list, &deep_transform(&1, fun))
  end

  defp deep_transform(string, fun) when is_binary(string) do
    fun.(string)
  end

  defp deep_transform(other, _fun), do: other

  defp deep_merge(left, right) do
    Map.merge(left, right, fn
      _k, %{} = l, %{} = r -> deep_merge(l, r)
      _k, _l, r -> r
    end)
  end

  defp atomize_keys(map) when is_map(map) do
    Map.new(map, fn {k, v} -> {String.to_atom(k), atomize_keys(v)} end)
  end

  defp atomize_keys(list) when is_list(list) do
    Enum.map(list, &atomize_keys/1)
  end

  defp atomize_keys(other), do: other
end
```

### 4.3 Manifest Resolver

```elixir
defmodule PortfolioCore.Manifest.Resolver do
  @moduledoc """
  Resolves manifest port configurations to concrete adapter modules
  and builds the wiring plan.
  """

  alias PortfolioCore.Manifest.AdapterRegistry

  @type wiring_plan :: %{
    ports: %{atom() => adapter_spec()},
    pipelines: %{atom() => pipeline_spec()},
    indexes: %{atom() => index_spec()},
    graphs: %{atom() => graph_spec()}
  }

  @type adapter_spec :: %{
    module: module(),
    config: map(),
    decorators: [decorator_spec()]
  }

  @type decorator_spec :: %{
    module: module(),
    config: map()
  }

  @spec resolve(manifest :: map()) :: {:ok, wiring_plan()} | {:error, term()}
  def resolve(manifest) do
    with {:ok, ports} <- resolve_ports(manifest.ports),
         {:ok, pipelines} <- resolve_pipelines(manifest.pipelines, ports),
         {:ok, indexes} <- resolve_indexes(manifest[:indexes] || %{}),
         {:ok, graphs} <- resolve_graphs(manifest[:graphs] || %{}) do
      {:ok, %{
        ports: ports,
        pipelines: pipelines,
        indexes: indexes,
        graphs: graphs,
        feature_flags: manifest[:feature_flags] || %{}
      }}
    end
  end

  defp resolve_ports(ports_config) do
    ports = Enum.reduce_while(ports_config, {:ok, %{}}, fn {port_name, config}, {:ok, acc} ->
      case resolve_port(port_name, config) do
        {:ok, spec} -> {:cont, {:ok, Map.put(acc, port_name, spec)}}
        {:error, _} = error -> {:halt, error}
      end
    end)

    ports
  end

  defp resolve_port(port_name, config) do
    with {:ok, module} <- AdapterRegistry.lookup(config.adapter),
         :ok <- validate_adapter_for_port(module, port_name),
         {:ok, decorators} <- resolve_decorators(config[:decorators] || []) do
      {:ok, %{
        module: module,
        config: config.config,
        decorators: decorators
      }}
    end
  end

  defp resolve_decorators(decorator_configs) do
    decorators = Enum.map(decorator_configs, fn config ->
      module = case config.type do
        "cached" -> PortfolioIndex.Adapters.Decorators.Cached
        "instrumented" -> PortfolioIndex.Adapters.Decorators.Instrumented
        other -> String.to_existing_atom("Elixir.#{Macro.camelize(other)}")
      end

      %{module: module, config: config[:config] || %{}}
    end)

    {:ok, decorators}
  end

  defp validate_adapter_for_port(adapter_module, port_name) do
    expected_port = port_behavior(port_name)
    adapter_port = adapter_module.port()

    if adapter_port == expected_port do
      :ok
    else
      {:error, {:port_mismatch, expected: expected_port, got: adapter_port}}
    end
  end

  defp port_behavior(:vector_store), do: PortfolioCore.Ports.VectorStorePort
  defp port_behavior(:graph_store), do: PortfolioCore.Ports.GraphStorePort
  defp port_behavior(:embedder), do: PortfolioCore.Ports.EmbedderPort
  defp port_behavior(:chunker), do: PortfolioCore.Ports.ChunkerPort
  defp port_behavior(:document_store), do: PortfolioCore.Ports.DocumentStorePort
  defp port_behavior(:audit), do: PortfolioCore.Ports.AuditPort

  defp resolve_pipelines(pipelines_config, ports) do
    # Resolve pipeline step references to port adapters
    {:ok, pipelines_config}
  end

  defp resolve_indexes(indexes_config) do
    {:ok, indexes_config}
  end

  defp resolve_graphs(graphs_config) do
    {:ok, graphs_config}
  end
end
```

### 4.4 Adapter Registry

```elixir
defmodule PortfolioCore.Manifest.AdapterRegistry do
  @moduledoc """
  Registry of available adapters, populated at compile time
  and runtime via plugin discovery.
  """

  use GenServer

  @builtin_adapters %{
    "portfolio_index.adapters.pgvector" => PortfolioIndex.Adapters.Pgvector,
    "portfolio_index.adapters.qdrant" => PortfolioIndex.Adapters.Qdrant,
    "portfolio_index.adapters.neo4j" => PortfolioIndex.Adapters.Neo4j,
    "portfolio_index.adapters.gemini" => PortfolioIndex.Adapters.Gemini,
    "portfolio_index.adapters.openai" => PortfolioIndex.Adapters.OpenAI,
    "portfolio_index.adapters.recursive_chunker" => PortfolioIndex.Adapters.RecursiveChunker
  }

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(_opts) do
    {:ok, %{adapters: @builtin_adapters}}
  end

  @doc """
  Lookup an adapter module by its manifest identifier.
  """
  def lookup(adapter_id) do
    GenServer.call(__MODULE__, {:lookup, adapter_id})
  end

  @doc """
  Register a custom adapter at runtime.
  """
  def register(adapter_id, module) do
    GenServer.call(__MODULE__, {:register, adapter_id, module})
  end

  @doc """
  List all registered adapters.
  """
  def list do
    GenServer.call(__MODULE__, :list)
  end

  @impl GenServer
  def handle_call({:lookup, adapter_id}, _from, state) do
    case Map.get(state.adapters, adapter_id) do
      nil -> {:reply, {:error, {:unknown_adapter, adapter_id}}, state}
      module -> {:reply, {:ok, module}, state}
    end
  end

  def handle_call({:register, adapter_id, module}, _from, state) do
    new_adapters = Map.put(state.adapters, adapter_id, module)
    {:reply, :ok, %{state | adapters: new_adapters}}
  end

  def handle_call(:list, _from, state) do
    {:reply, state.adapters, state}
  end
end
```

---

## 5. Domain Model Purity

### 5.1 Value Objects

```elixir
defmodule PortfolioCore.Domain.Chunk do
  @moduledoc """
  Value object representing a document chunk.
  Immutable, no database dependencies.
  """

  @type t :: %__MODULE__{
    id: String.t() | nil,
    content: String.t(),
    index: non_neg_integer(),
    start_offset: non_neg_integer(),
    end_offset: non_neg_integer(),
    embedding: [float()] | nil,
    metadata: map()
  }

  defstruct [:id, :content, :index, :start_offset, :end_offset, :embedding, metadata: %{}]

  def new(attrs) do
    struct!(__MODULE__, attrs)
  end

  def with_embedding(%__MODULE__{} = chunk, embedding) do
    %{chunk | embedding: embedding}
  end

  def content_hash(%__MODULE__{content: content}) do
    :crypto.hash(:sha256, content) |> Base.encode16(case: :lower)
  end
end

defmodule PortfolioCore.Domain.Entity do
  @moduledoc """
  Value object representing a graph entity.
  """

  @type t :: %__MODULE__{
    id: String.t() | nil,
    graph_id: String.t(),
    type: String.t(),
    name: String.t(),
    properties: map(),
    embedding: [float()] | nil,
    source_chunk_ids: [String.t()]
  }

  defstruct [:id, :graph_id, :type, :name, :embedding,
             properties: %{}, source_chunk_ids: []]

  def new(attrs) do
    struct!(__MODULE__, attrs)
  end
end

defmodule PortfolioCore.Domain.Edge do
  @moduledoc """
  Value object representing a graph edge.
  """

  @type t :: %__MODULE__{
    id: String.t() | nil,
    graph_id: String.t(),
    from_id: String.t(),
    to_id: String.t(),
    type: String.t(),
    weight: float(),
    properties: map()
  }

  defstruct [:id, :graph_id, :from_id, :to_id, :type, weight: 1.0, properties: %{}]

  def new(attrs) do
    struct!(__MODULE__, attrs)
  end
end
```

### 5.2 Domain Services

```elixir
defmodule PortfolioCore.Domain.IngestionService do
  @moduledoc """
  Domain service for document ingestion.
  No infrastructure dependencies - receives port implementations as arguments.
  """

  alias PortfolioCore.Domain.{Chunk, Entity}

  @type ingestion_result :: %{
    chunks_stored: non_neg_integer(),
    entities_extracted: non_neg_integer(),
    edges_created: non_neg_integer()
  }

  @doc """
  Ingest a document through the full pipeline.

  Receives port implementations as a map to maintain domain purity.
  """
  @spec ingest_document(
    document :: map(),
    ports :: %{
      chunker: module(),
      embedder: module(),
      vector_store: module(),
      graph_store: module()
    },
    opts :: keyword()
  ) :: {:ok, ingestion_result()} | {:error, term()}
  def ingest_document(document, ports, opts \\ []) do
    with {:ok, chunks} <- chunk_document(document, ports.chunker, opts),
         {:ok, embedded_chunks} <- embed_chunks(chunks, ports.embedder),
         {:ok, chunk_ids} <- store_chunks(embedded_chunks, ports.vector_store),
         {:ok, entities} <- extract_entities(embedded_chunks, opts),
         {:ok, entity_ids} <- store_entities(entities, ports.graph_store),
         {:ok, edges} <- infer_edges(entities, opts),
         {:ok, _edge_ids} <- store_edges(edges, ports.graph_store) do
      {:ok, %{
        chunks_stored: length(chunk_ids),
        entities_extracted: length(entity_ids),
        edges_created: length(edges)
      }}
    end
  end

  defp chunk_document(document, chunker, opts) do
    strategy = Keyword.get(opts, :chunk_strategy, :recursive)
    chunker.chunk(document.content, strategy: strategy)
  end

  defp embed_chunks(chunks, embedder) do
    contents = Enum.map(chunks, & &1.content)

    case embedder.embed_batch(contents, []) do
      {:ok, embeddings} ->
        embedded = Enum.zip_with(chunks, embeddings, fn chunk, embedding ->
          Chunk.with_embedding(chunk, embedding)
        end)
        {:ok, embedded}

      error ->
        error
    end
  end

  defp store_chunks(chunks, vector_store) do
    chunk_maps = Enum.map(chunks, fn chunk ->
      %{
        content: chunk.content,
        embedding: chunk.embedding,
        metadata: chunk.metadata
      }
    end)

    vector_store.store_chunks(chunk_maps)
  end

  defp extract_entities(chunks, _opts) do
    # Entity extraction logic (could delegate to an extractor port)
    entities = Enum.flat_map(chunks, fn chunk ->
      # Simplified - would use NER or LLM extraction
      []
    end)
    {:ok, entities}
  end

  defp store_entities(entities, graph_store) do
    graph_store.insert_entities(entities)
  end

  defp infer_edges(entities, _opts) do
    # Edge inference logic
    {:ok, []}
  end

  defp store_edges(edges, graph_store) do
    graph_store.insert_edges(edges)
  end
end
```

### 5.3 Domain Events

```elixir
defmodule PortfolioCore.Domain.Events do
  @moduledoc """
  Domain events for the portfolio system.
  """

  defmodule DocumentIngested do
    defstruct [:document_id, :repo_id, :path, :chunk_count, :timestamp]
  end

  defmodule ChunksStored do
    defstruct [:document_id, :chunk_ids, :index_id, :timestamp]
  end

  defmodule EntitiesExtracted do
    defstruct [:document_id, :graph_id, :entity_ids, :timestamp]
  end

  defmodule GraphUpdated do
    defstruct [:graph_id, :entities_added, :edges_added, :timestamp]
  end

  defmodule QueryExecuted do
    defstruct [:query_id, :query_text, :result_count, :duration_ms, :timestamp]
  end
end
```

---

## 6. Publishing portfolio_core to Hex

### 6.1 Package Structure

```
portfolio_core/
├── lib/
│   ├── portfolio_core.ex           # Main module, facade
│   ├── domain/
│   │   ├── chunk.ex                # Value objects
│   │   ├── entity.ex
│   │   ├── edge.ex
│   │   ├── community.ex
│   │   ├── document.ex
│   │   ├── ingestion_service.ex    # Domain services
│   │   ├── retrieval_service.ex
│   │   └── events.ex               # Domain events
│   ├── ports/
│   │   ├── vector_store_port.ex
│   │   ├── graph_store_port.ex
│   │   ├── embedder_port.ex
│   │   ├── chunker_port.ex
│   │   ├── document_store_port.ex
│   │   └── audit_port.ex
│   └── manifest/
│       ├── parser.ex
│       ├── resolver.ex
│       ├── schema.ex
│       └── adapter_registry.ex
├── mix.exs
├── README.md
└── LICENSE
```

### 6.2 mix.exs for portfolio_core

```elixir
defmodule PortfolioCore.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/yourorg/portfolio_core"

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
      source_url: @source_url
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # ZERO external dependencies for the core!
  defp deps do
    [
      {:yaml_elixir, "~> 2.9", optional: true},
      {:nimble_options, "~> 1.0", optional: true},
      {:ex_doc, "~> 0.30", only: :dev, runtime: false}
    ]
  end

  defp description do
    """
    Pure hexagonal core for building manifest-driven RAG ecosystems.
    Defines ports, domain models, and manifest engine without infrastructure dependencies.
    """
  end

  defp package do
    [
      name: "portfolio_core",
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url},
      files: ~w(lib .formatter.exs mix.exs README.md LICENSE)
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: ["README.md"],
      source_ref: "v#{@version}"
    ]
  end
end
```

---

## 7. Complete Port Behavior Definitions

See Section 2 for complete specifications of all ports:

- `VectorStorePort` - 15 callbacks for vector storage and search
- `GraphStorePort` - 20 callbacks for graph operations
- `EmbedderPort` - 7 callbacks for embedding generation
- `ChunkerPort` - 4 callbacks for content chunking
- `DocumentStorePort` - 8 callbacks for document persistence
- `AuditPort` - 4 callbacks for audit logging

Each port defines:
- Type specifications for all data structures
- Required callbacks with clear contracts
- Optional callbacks for advanced features
- Documentation for implementers

---

## Summary

This hexagonal core design provides:

1. **Pure domain isolation** - Zero infrastructure dependencies in portfolio_core
2. **Manifest-driven wiring** - YAML/JSON manifests configure all adapters
3. **Complete port specifications** - Well-defined behaviors for all extension points
4. **Adapter patterns** - Decorators for caching, metrics, circuit breaking
5. **Publishable package** - portfolio_core ready for Hex.pm
6. **Domain purity** - Value objects, services, and events with no DB coupling

The architecture enables infinite extensibility while maintaining a stable, testable core.
