# BEAM/OTP Architecture for Scalable RAG Ecosystem

**Expert:** Dr. Elara Voss, Senior Fellow BEAM/OTP Architecture
**Experience:** 20+ years at WhatsApp, Discord, Ericsson

---

## Table of Contents

1. [Supervision Tree Architecture](#supervision-tree-architecture)
2. [Dynamic Process Management](#dynamic-process-management)
3. [Registry Patterns for Multi-Store](#registry-patterns-for-multi-store)
4. [GenStage/Broadway Pipeline Patterns](#genstagebroadway-pipeline-patterns)
5. [Distribution and Clustering](#distribution-and-clustering)
6. [Fault Tolerance Patterns](#fault-tolerance-patterns)
7. [State Management at Scale](#state-management-at-scale)
8. [Complete OTP Architecture](#complete-otp-architecture)

---

## 1. Supervision Tree Architecture

### 1.1 Root Application Supervision

```elixir
defmodule PortfolioManager.Application do
  use Application

  def start(_type, _args) do
    children = [
      # Core infrastructure (start first)
      {Registry, keys: :unique, name: PortfolioManager.Registry},
      {Registry, keys: :duplicate, name: PortfolioManager.PubSub},

      # Manifest-driven adapter supervisor
      {PortfolioManager.AdapterSupervisor, manifest: load_manifest()},

      # Pipeline supervisors
      {PortfolioManager.Pipelines.IngestSupervisor, []},
      {PortfolioManager.Pipelines.QuerySupervisor, []},

      # Cache layer
      {PortfolioManager.Cache.Supervisor, []},

      # Telemetry
      PortfolioManager.Telemetry
    ]

    opts = [strategy: :one_for_one, name: PortfolioManager.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp load_manifest do
    env = Application.get_env(:portfolio_manager, :environment, :dev)
    PortfolioCore.Manifest.load!("config/manifests/#{env}.yaml")
  end
end
```

### 1.2 Adapter Supervisor (Dynamic)

```elixir
defmodule PortfolioManager.AdapterSupervisor do
  use Supervisor

  def start_link(opts) do
    manifest = Keyword.fetch!(opts, :manifest)
    Supervisor.start_link(__MODULE__, manifest, name: __MODULE__)
  end

  @impl true
  def init(manifest) do
    children = build_adapter_specs(manifest)
    Supervisor.init(children, strategy: :one_for_one)
  end

  defp build_adapter_specs(%{ports: ports}) do
    Enum.flat_map(ports, fn {port_name, port_config} ->
      adapter_module = resolve_adapter(port_config.adapter)

      case port_config[:pool] do
        nil ->
          # Single process adapter
          [{adapter_module, [name: via_registry(port_name), config: port_config.config]}]

        pool_config ->
          # Pooled adapter (e.g., database connections)
          [{PortfolioManager.AdapterPool,
            [name: via_registry(port_name),
             adapter: adapter_module,
             pool_size: pool_config[:size] || 10,
             config: port_config.config]}]
      end
    end)
  end

  defp resolve_adapter(adapter_string) do
    # "portfolio_index.adapters.neo4j" -> PortfolioIndex.Adapters.Neo4j
    adapter_string
    |> String.split(".")
    |> Enum.map(&Macro.camelize/1)
    |> Module.concat()
  end

  defp via_registry(port_name) do
    {:via, Registry, {PortfolioManager.Registry, {:port, port_name}}}
  end
end
```

### 1.3 Multi-Instance Adapter Supervision

For multi-graph and multi-vector scenarios:

```elixir
defmodule PortfolioManager.MultiInstanceSupervisor do
  use DynamicSupervisor

  def start_link(opts) do
    DynamicSupervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  @doc """
  Start a new graph store instance for a specific graph_id.
  """
  def start_graph_instance(graph_id, adapter_module, config) do
    child_spec = %{
      id: {:graph_store, graph_id},
      start: {adapter_module, :start_link, [[
        name: via_registry({:graph, graph_id}),
        graph_id: graph_id,
        config: config
      ]]},
      restart: :permanent,
      type: :worker
    }

    DynamicSupervisor.start_child(__MODULE__, child_spec)
  end

  @doc """
  Start a new vector index instance.
  """
  def start_vector_instance(index_id, adapter_module, config) do
    child_spec = %{
      id: {:vector_store, index_id},
      start: {adapter_module, :start_link, [[
        name: via_registry({:vector, index_id}),
        index_id: index_id,
        config: config
      ]]},
      restart: :permanent,
      type: :worker
    }

    DynamicSupervisor.start_child(__MODULE__, child_spec)
  end

  defp via_registry(key) do
    {:via, Registry, {PortfolioManager.Registry, key}}
  end
end
```

---

## 2. Dynamic Process Management

### 2.1 Adapter Pool with NimblePool

```elixir
defmodule PortfolioManager.AdapterPool do
  @moduledoc """
  Connection pool for adapters that need pooled resources (DB connections, etc.)
  """

  use GenServer

  defstruct [:adapter, :pool_size, :config, :pool_ref]

  def start_link(opts) do
    name = Keyword.fetch!(opts, :name)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @impl true
  def init(opts) do
    adapter = Keyword.fetch!(opts, :adapter)
    pool_size = Keyword.get(opts, :pool_size, 10)
    config = Keyword.fetch!(opts, :config)

    pool_opts = [
      worker: {adapter, config},
      pool_size: pool_size,
      lazy: true
    ]

    {:ok, pool_ref} = NimblePool.start_link(pool_opts)

    {:ok, %__MODULE__{
      adapter: adapter,
      pool_size: pool_size,
      config: config,
      pool_ref: pool_ref
    }}
  end

  def checkout(pool, fun, timeout \\ 5000) do
    GenServer.call(pool, {:checkout, fun, timeout})
  end

  @impl true
  def handle_call({:checkout, fun, timeout}, _from, state) do
    result = NimblePool.checkout!(state.pool_ref, :checkout, fn _from, worker ->
      result = fun.(worker)
      {:ok, result, worker}
    end, timeout)

    {:reply, result, state}
  end
end
```

### 2.2 Circuit Breaker for External Services

```elixir
defmodule PortfolioManager.CircuitBreaker do
  @moduledoc """
  Circuit breaker pattern for external service calls (LLM APIs, etc.)
  """

  use GenServer

  defstruct [
    :name,
    :failure_threshold,
    :recovery_time,
    :state,  # :closed, :open, :half_open
    :failure_count,
    :last_failure_time
  ]

  def start_link(opts) do
    name = Keyword.fetch!(opts, :name)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @impl true
  def init(opts) do
    {:ok, %__MODULE__{
      name: Keyword.fetch!(opts, :name),
      failure_threshold: Keyword.get(opts, :failure_threshold, 5),
      recovery_time: Keyword.get(opts, :recovery_time, 30_000),
      state: :closed,
      failure_count: 0,
      last_failure_time: nil
    }}
  end

  def call(breaker, fun) do
    GenServer.call(breaker, {:call, fun})
  end

  @impl true
  def handle_call({:call, fun}, _from, %{state: :open} = state) do
    if should_attempt_recovery?(state) do
      execute_with_tracking(fun, %{state | state: :half_open})
    else
      {:reply, {:error, :circuit_open}, state}
    end
  end

  def handle_call({:call, fun}, _from, state) do
    execute_with_tracking(fun, state)
  end

  defp execute_with_tracking(fun, state) do
    case fun.() do
      {:ok, result} ->
        new_state = %{state | state: :closed, failure_count: 0}
        {:reply, {:ok, result}, new_state}

      {:error, reason} ->
        new_state = record_failure(state)
        {:reply, {:error, reason}, new_state}
    end
  end

  defp record_failure(state) do
    new_count = state.failure_count + 1
    new_state = if new_count >= state.failure_threshold do
      :open
    else
      state.state
    end

    %{state |
      failure_count: new_count,
      state: new_state,
      last_failure_time: System.monotonic_time(:millisecond)
    }
  end

  defp should_attempt_recovery?(state) do
    now = System.monotonic_time(:millisecond)
    now - state.last_failure_time > state.recovery_time
  end
end
```

---

## 3. Registry Patterns for Multi-Store

### 3.1 Hierarchical Registry Keys

```elixir
defmodule PortfolioManager.StoreRegistry do
  @moduledoc """
  Registry patterns for managing multi-graph and multi-vector instances.

  Key patterns:
  - {:port, port_name}              -> Primary port adapter
  - {:graph, graph_id}              -> Graph store for specific graph
  - {:vector, index_id}             -> Vector store for specific index
  - {:pipeline, pipeline_id}        -> Active pipeline instance
  - {:cache, namespace}             -> Cache partition
  """

  def lookup_port(port_name) do
    case Registry.lookup(PortfolioManager.Registry, {:port, port_name}) do
      [{pid, _}] -> {:ok, pid}
      [] -> {:error, :not_found}
    end
  end

  def lookup_graph(graph_id) do
    case Registry.lookup(PortfolioManager.Registry, {:graph, graph_id}) do
      [{pid, _}] -> {:ok, pid}
      [] -> {:error, :not_found}
    end
  end

  def lookup_vector(index_id) do
    case Registry.lookup(PortfolioManager.Registry, {:vector, index_id}) do
      [{pid, _}] -> {:ok, pid}
      [] -> {:error, :not_found}
    end
  end

  @doc """
  Get or create a graph store instance.
  """
  def get_or_create_graph(graph_id, adapter_module, config) do
    case lookup_graph(graph_id) do
      {:ok, pid} -> {:ok, pid}
      {:error, :not_found} ->
        PortfolioManager.MultiInstanceSupervisor.start_graph_instance(
          graph_id, adapter_module, config
        )
    end
  end

  @doc """
  List all active graph instances.
  """
  def list_graphs do
    Registry.select(PortfolioManager.Registry, [
      {{{:graph, :"$1"}, :"$2", :_}, [], [{{:"$1", :"$2"}}]}
    ])
  end

  @doc """
  List all active vector indexes.
  """
  def list_vector_indexes do
    Registry.select(PortfolioManager.Registry, [
      {{{:vector, :"$1"}, :"$2", :_}, [], [{{:"$1", :"$2"}}]}
    ])
  end
end
```

### 3.2 Port Router

```elixir
defmodule PortfolioManager.PortRouter do
  @moduledoc """
  Routes operations to the appropriate adapter based on manifest configuration
  and runtime context.
  """

  @doc """
  Route a vector search to the appropriate index based on query context.
  """
  def route_vector_query(query, opts \\ []) do
    index_id = determine_vector_index(query, opts)

    case PortfolioManager.StoreRegistry.lookup_vector(index_id) do
      {:ok, pid} -> {:ok, pid}
      {:error, :not_found} -> {:error, {:no_index, index_id}}
    end
  end

  @doc """
  Route a graph operation to the appropriate graph store.
  """
  def route_graph_operation(operation, opts \\ []) do
    graph_id = Keyword.get(opts, :graph_id) || :default

    case PortfolioManager.StoreRegistry.lookup_graph(graph_id) do
      {:ok, pid} -> {:ok, pid}
      {:error, :not_found} -> {:error, {:no_graph, graph_id}}
    end
  end

  defp determine_vector_index(query, opts) do
    cond do
      Keyword.has_key?(opts, :index_id) ->
        Keyword.get(opts, :index_id)

      is_code_query?(query) ->
        :code_dense

      true ->
        :docs_dense
    end
  end

  defp is_code_query?(query) do
    # Heuristic: contains code-like tokens
    String.contains?(query, ["def ", "function ", "class ", "->", "=>"])
  end
end
```

---

## 4. GenStage/Broadway Pipeline Patterns

### 4.1 Broadway Ingestion Pipeline

```elixir
defmodule PortfolioManager.Pipelines.IngestPipeline do
  use Broadway

  @impl true
  def start_link(opts) do
    pipeline_id = Keyword.fetch!(opts, :pipeline_id)

    Broadway.start_link(__MODULE__,
      name: via_registry(pipeline_id),
      producer: [
        module: {PortfolioManager.Pipelines.FileProducer, opts},
        concurrency: 1
      ],
      processors: [
        chunk: [concurrency: 4],
        embed: [concurrency: 2]  # Rate limited for API calls
      ],
      batchers: [
        vector_store: [concurrency: 2, batch_size: 100, batch_timeout: 1000],
        graph_store: [concurrency: 1, batch_size: 50, batch_timeout: 2000]
      ],
      partition_by: &partition_by_repo/1
    )
  end

  @impl true
  def handle_message(:chunk, message, context) do
    file = message.data

    chunks = context.chunker.chunk(file.content, file.path)

    messages = Enum.map(chunks, fn chunk ->
      Broadway.Message.put_data(message, %{
        chunk: chunk,
        file: file,
        repo_id: file.repo_id
      })
    end)

    {:ok, messages}
  end

  @impl true
  def handle_message(:embed, message, context) do
    %{chunk: chunk} = message.data

    case context.embedder.embed(chunk.content) do
      {:ok, embedding} ->
        message
        |> Broadway.Message.put_data(Map.put(message.data, :embedding, embedding))
        |> Broadway.Message.put_batcher(:vector_store)

      {:error, reason} ->
        Broadway.Message.failed(message, reason)
    end
  end

  @impl true
  def handle_batch(:vector_store, messages, _batch_info, context) do
    chunks = Enum.map(messages, fn msg ->
      %{
        content: msg.data.chunk.content,
        embedding: msg.data.embedding,
        metadata: %{
          repo_id: msg.data.repo_id,
          path: msg.data.file.path,
          chunk_index: msg.data.chunk.index
        }
      }
    end)

    case context.vector_store.insert_batch(chunks) do
      {:ok, _} -> messages
      {:error, reason} -> Enum.map(messages, &Broadway.Message.failed(&1, reason))
    end
  end

  @impl true
  def handle_batch(:graph_store, messages, _batch_info, context) do
    entities = extract_entities_from_batch(messages, context)

    case context.graph_store.insert_entities(entities) do
      {:ok, _} -> messages
      {:error, reason} -> Enum.map(messages, &Broadway.Message.failed(&1, reason))
    end
  end

  defp partition_by_repo(%{data: %{repo_id: repo_id}}) do
    :erlang.phash2(repo_id)
  end

  defp partition_by_repo(_), do: 0

  defp via_registry(pipeline_id) do
    {:via, Registry, {PortfolioManager.Registry, {:pipeline, pipeline_id}}}
  end

  defp extract_entities_from_batch(messages, context) do
    # Extract entities from chunks for graph storage
    Enum.flat_map(messages, fn msg ->
      context.entity_extractor.extract(msg.data.chunk.content)
    end)
  end
end
```

### 4.2 Rate-Limited Embedding Producer

```elixir
defmodule PortfolioManager.Pipelines.RateLimitedEmbedder do
  @moduledoc """
  GenStage producer-consumer that rate-limits embedding API calls.
  """

  use GenStage

  defstruct [
    :embedder,
    :rate_limit,
    :window_ms,
    :current_count,
    :window_start,
    pending: :queue.new()
  ]

  def start_link(opts) do
    GenStage.start_link(__MODULE__, opts)
  end

  @impl true
  def init(opts) do
    state = %__MODULE__{
      embedder: Keyword.fetch!(opts, :embedder),
      rate_limit: Keyword.get(opts, :rate_limit, 100),
      window_ms: Keyword.get(opts, :window_ms, 60_000),
      current_count: 0,
      window_start: System.monotonic_time(:millisecond)
    }

    {:producer_consumer, state}
  end

  @impl true
  def handle_events(events, _from, state) do
    now = System.monotonic_time(:millisecond)
    state = maybe_reset_window(state, now)

    {to_process, to_queue, new_count} =
      split_by_rate_limit(events, state.rate_limit - state.current_count)

    results = process_batch(to_process, state.embedder)

    new_state = %{state |
      current_count: new_count,
      pending: enqueue_all(state.pending, to_queue)
    }

    if not :queue.is_empty(new_state.pending) do
      schedule_drain()
    end

    {:noreply, results, new_state}
  end

  @impl true
  def handle_info(:drain_pending, state) do
    now = System.monotonic_time(:millisecond)
    state = maybe_reset_window(state, now)

    available = state.rate_limit - state.current_count
    {to_process, remaining} = dequeue_n(state.pending, available)

    results = process_batch(to_process, state.embedder)

    new_state = %{state |
      current_count: state.current_count + length(to_process),
      pending: remaining
    }

    if not :queue.is_empty(new_state.pending) do
      schedule_drain()
    end

    {:noreply, results, new_state}
  end

  defp maybe_reset_window(state, now) do
    if now - state.window_start > state.window_ms do
      %{state | current_count: 0, window_start: now}
    else
      state
    end
  end

  defp split_by_rate_limit(events, available) do
    {to_process, to_queue} = Enum.split(events, max(0, available))
    {to_process, to_queue, length(to_process)}
  end

  defp process_batch(events, embedder) do
    Enum.map(events, fn event ->
      case embedder.embed(event.data.content) do
        {:ok, embedding} -> Map.put(event, :embedding, embedding)
        {:error, _} = error -> Map.put(event, :error, error)
      end
    end)
  end

  defp schedule_drain do
    Process.send_after(self(), :drain_pending, 100)
  end

  defp enqueue_all(queue, items) do
    Enum.reduce(items, queue, &:queue.in/2)
  end

  defp dequeue_n(queue, n) do
    dequeue_n(queue, n, [])
  end

  defp dequeue_n(queue, 0, acc), do: {Enum.reverse(acc), queue}
  defp dequeue_n(queue, n, acc) do
    case :queue.out(queue) do
      {{:value, item}, rest} -> dequeue_n(rest, n - 1, [item | acc])
      {:empty, queue} -> {Enum.reverse(acc), queue}
    end
  end
end
```

---

## 5. Distribution and Clustering

### 5.1 Cluster Configuration with libcluster

```elixir
# config/runtime.exs
config :libcluster,
  topologies: [
    k8s: [
      strategy: Cluster.Strategy.Kubernetes.DNS,
      config: [
        service: "portfolio-manager-headless",
        application_name: "portfolio_manager"
      ]
    ],
    gossip: [
      strategy: Cluster.Strategy.Gossip,
      config: [
        port: 45892,
        if_addr: "0.0.0.0",
        multicast_if: "eth0",
        multicast_addr: "230.1.1.251",
        multicast_ttl: 1
      ]
    ]
  ]
```

### 5.2 Distributed Registry with Horde

```elixir
defmodule PortfolioManager.DistributedRegistry do
  @moduledoc """
  Distributed process registry using Horde for multi-node deployments.
  """

  use Horde.Registry

  def start_link(_opts) do
    Horde.Registry.start_link(__MODULE__, [keys: :unique], name: __MODULE__)
  end

  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      type: :supervisor
    }
  end

  @impl true
  def init(init_arg) do
    [members: members()]
    |> Keyword.merge(init_arg)
    |> Horde.Registry.init()
  end

  defp members do
    [Node.self() | Node.list()]
    |> Enum.map(fn node -> {__MODULE__, node} end)
  end

  # Called when cluster membership changes
  def on_cluster_change do
    Horde.Cluster.set_members(__MODULE__, members())
  end
end

defmodule PortfolioManager.DistributedSupervisor do
  @moduledoc """
  Distributed dynamic supervisor using Horde.
  Adapters started here are automatically distributed across the cluster.
  """

  use Horde.DynamicSupervisor

  def start_link(_opts) do
    Horde.DynamicSupervisor.start_link(__MODULE__, [strategy: :one_for_one], name: __MODULE__)
  end

  @impl true
  def init(init_arg) do
    [members: members()]
    |> Keyword.merge(init_arg)
    |> Horde.DynamicSupervisor.init()
  end

  defp members do
    [Node.self() | Node.list()]
    |> Enum.map(fn node -> {__MODULE__, node} end)
  end

  def start_adapter(adapter_spec) do
    Horde.DynamicSupervisor.start_child(__MODULE__, adapter_spec)
  end

  def on_cluster_change do
    Horde.Cluster.set_members(__MODULE__, members())
  end
end
```

### 5.3 Distributed PubSub for Events

```elixir
defmodule PortfolioManager.PubSub do
  @moduledoc """
  Distributed event bus for cross-node communication.
  """

  def child_spec(_opts) do
    Phoenix.PubSub.child_spec(name: __MODULE__)
  end

  def subscribe(topic) do
    Phoenix.PubSub.subscribe(__MODULE__, topic)
  end

  def broadcast(topic, message) do
    Phoenix.PubSub.broadcast(__MODULE__, topic, message)
  end

  def broadcast_from(from_pid, topic, message) do
    Phoenix.PubSub.broadcast_from(__MODULE__, from_pid, topic, message)
  end

  # Topic patterns
  def graph_topic(graph_id), do: "graph:#{graph_id}"
  def vector_topic(index_id), do: "vector:#{index_id}"
  def pipeline_topic(pipeline_id), do: "pipeline:#{pipeline_id}"
  def repo_topic(repo_id), do: "repo:#{repo_id}"
end
```

---

## 6. Fault Tolerance Patterns

### 6.1 Graceful Degradation Supervisor

```elixir
defmodule PortfolioManager.GracefulDegradation do
  @moduledoc """
  Manages graceful degradation when adapters fail.
  Falls back to alternative adapters or cached results.
  """

  use GenServer

  defstruct [
    :primary_adapters,
    :fallback_adapters,
    :health_status
  ]

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(opts) do
    state = %__MODULE__{
      primary_adapters: Keyword.get(opts, :primary, %{}),
      fallback_adapters: Keyword.get(opts, :fallback, %{}),
      health_status: %{}
    }

    schedule_health_check()
    {:ok, state}
  end

  @doc """
  Get the best available adapter for a port.
  """
  def get_adapter(port_name) do
    GenServer.call(__MODULE__, {:get_adapter, port_name})
  end

  @doc """
  Report an adapter failure.
  """
  def report_failure(port_name, adapter_id, reason) do
    GenServer.cast(__MODULE__, {:failure, port_name, adapter_id, reason})
  end

  @impl true
  def handle_call({:get_adapter, port_name}, _from, state) do
    adapter = case Map.get(state.health_status, port_name) do
      :healthy ->
        Map.get(state.primary_adapters, port_name)

      :degraded ->
        Map.get(state.fallback_adapters, port_name) ||
          Map.get(state.primary_adapters, port_name)

      _ ->
        Map.get(state.primary_adapters, port_name)
    end

    {:reply, {:ok, adapter}, state}
  end

  @impl true
  def handle_cast({:failure, port_name, _adapter_id, _reason}, state) do
    new_status = Map.put(state.health_status, port_name, :degraded)
    PortfolioManager.PubSub.broadcast("system:health", {:degraded, port_name})
    {:noreply, %{state | health_status: new_status}}
  end

  @impl true
  def handle_info(:health_check, state) do
    new_status = check_all_adapters(state)
    schedule_health_check()
    {:noreply, %{state | health_status: new_status}}
  end

  defp schedule_health_check do
    Process.send_after(self(), :health_check, 30_000)
  end

  defp check_all_adapters(state) do
    Enum.reduce(state.primary_adapters, %{}, fn {port_name, adapter}, acc ->
      status = check_adapter_health(adapter)
      Map.put(acc, port_name, status)
    end)
  end

  defp check_adapter_health(adapter) do
    case adapter.health_check() do
      :ok -> :healthy
      {:error, _} -> :degraded
    end
  end
end
```

### 6.2 Retry with Exponential Backoff

```elixir
defmodule PortfolioManager.Retry do
  @moduledoc """
  Retry utilities with exponential backoff for external service calls.
  """

  @default_opts [
    max_attempts: 3,
    base_delay: 100,
    max_delay: 10_000,
    jitter: true
  ]

  def with_retry(fun, opts \\ []) do
    opts = Keyword.merge(@default_opts, opts)
    do_retry(fun, 1, opts)
  end

  defp do_retry(fun, attempt, opts) do
    case fun.() do
      {:ok, result} ->
        {:ok, result}

      {:error, reason} when attempt < opts[:max_attempts] ->
        delay = calculate_delay(attempt, opts)
        Process.sleep(delay)
        do_retry(fun, attempt + 1, opts)

      {:error, reason} ->
        {:error, {:max_retries_exceeded, reason}}
    end
  end

  defp calculate_delay(attempt, opts) do
    base = opts[:base_delay] * :math.pow(2, attempt - 1)
    delay = min(trunc(base), opts[:max_delay])

    if opts[:jitter] do
      jitter = :rand.uniform(div(delay, 2))
      delay + jitter
    else
      delay
    end
  end
end
```

---

## 7. State Management at Scale

### 7.1 ETS-Based Caching

```elixir
defmodule PortfolioManager.Cache.ETS do
  @moduledoc """
  ETS-based cache for embeddings and query results.
  """

  use GenServer

  @table_name :portfolio_cache
  @default_ttl 3600_000  # 1 hour in milliseconds

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    table = :ets.new(@table_name, [
      :set,
      :public,
      :named_table,
      read_concurrency: true,
      write_concurrency: true
    ])

    schedule_cleanup()
    {:ok, %{table: table}}
  end

  def get(namespace, key) do
    full_key = {namespace, key}

    case :ets.lookup(@table_name, full_key) do
      [{^full_key, value, expires_at}] ->
        if System.monotonic_time(:millisecond) < expires_at do
          {:ok, value}
        else
          :ets.delete(@table_name, full_key)
          {:error, :not_found}
        end

      [] ->
        {:error, :not_found}
    end
  end

  def put(namespace, key, value, ttl \\ @default_ttl) do
    full_key = {namespace, key}
    expires_at = System.monotonic_time(:millisecond) + ttl
    :ets.insert(@table_name, {full_key, value, expires_at})
    :ok
  end

  def delete(namespace, key) do
    :ets.delete(@table_name, {namespace, key})
    :ok
  end

  def clear_namespace(namespace) do
    :ets.match_delete(@table_name, {{namespace, :_}, :_, :_})
    :ok
  end

  @impl true
  def handle_info(:cleanup, state) do
    now = System.monotonic_time(:millisecond)

    :ets.select_delete(@table_name, [
      {{:_, :_, :"$1"}, [{:<, :"$1", now}], [true]}
    ])

    schedule_cleanup()
    {:noreply, state}
  end

  defp schedule_cleanup do
    Process.send_after(self(), :cleanup, 60_000)
  end
end
```

### 7.2 Persistent Term for Manifests

```elixir
defmodule PortfolioManager.ManifestStore do
  @moduledoc """
  Stores parsed manifests in persistent_term for fast, concurrent reads.
  """

  @key :portfolio_manifest

  def load!(manifest_path) do
    manifest = PortfolioCore.Manifest.parse!(manifest_path)
    :persistent_term.put(@key, manifest)
    manifest
  end

  def get do
    :persistent_term.get(@key)
  end

  def get_port(port_name) do
    manifest = get()
    Map.get(manifest.ports, port_name)
  end

  def get_pipeline(pipeline_name) do
    manifest = get()
    Map.get(manifest.pipelines, pipeline_name)
  end

  def reload!(manifest_path) do
    # Gracefully reload - old value remains accessible until new one is set
    load!(manifest_path)
  end
end
```

---

## 8. Complete OTP Architecture

### 8.1 Full Supervision Tree Diagram

```
                              PortfolioManager.Supervisor
                                         │
                    ┌────────────────────┼────────────────────┐
                    │                    │                    │
            Registry (unique)    Registry (pubsub)    Telemetry
                    │
    ┌───────────────┼───────────────┐
    │               │               │
AdapterSupervisor  PipelineSup   CacheSupervisor
    │               │               │
    ├─VectorStore   ├─IngestPipe   ├─ETS Cache
    ├─GraphStore    ├─QueryPipe    └─Embedding Cache
    ├─Embedder      └─EvalPipe
    └─Chunker

    MultiInstanceSupervisor (DynamicSupervisor)
    │
    ├─{:graph, "repo_1"} -> GraphAdapter
    ├─{:graph, "repo_2"} -> GraphAdapter
    ├─{:vector, "code_dense"} -> VectorAdapter
    └─{:vector, "docs_dense"} -> VectorAdapter

    GracefulDegradation (health monitoring)

    CircuitBreakers
    ├─:llm_api
    ├─:embedding_api
    └─:neo4j
```

### 8.2 Message Flow Diagram

```
User Request
     │
     ▼
CLI/HTTP Handler
     │
     ▼
PortRouter.route_query(query, opts)
     │
     ├─lookup Vector Index ──► VectorStore.search(embedding)
     │                              │
     │                              ▼
     │                         EmbedderPort ──► CircuitBreaker ──► Gemini API
     │
     ├─lookup Graph ──► GraphStore.traverse(entity, depth)
     │
     └─combine results ──► Reranker ──► Response
```

### 8.3 Initialization Sequence

```elixir
# 1. Application starts
PortfolioManager.Application.start()

# 2. Load manifest from persistent_term
manifest = PortfolioManager.ManifestStore.load!("config/manifests/dev.yaml")

# 3. AdapterSupervisor reads manifest and starts adapters
#    Each port in manifest.ports gets an adapter process

# 4. MultiInstanceSupervisor starts (empty)
#    Graph/vector instances created on-demand

# 5. PipelineSupervisor starts Broadway pipelines
#    Pipelines read from manifest.pipelines

# 6. GracefulDegradation starts health monitoring

# 7. System ready for requests
```

---

## Summary

This BEAM/OTP architecture provides:

1. **Dynamic adapter management** via manifest-driven supervision
2. **Multi-instance support** for graphs and vectors via DynamicSupervisor
3. **Fault tolerance** with circuit breakers and graceful degradation
4. **Backpressure handling** via Broadway and GenStage
5. **Distribution ready** with Horde and libcluster
6. **Fast configuration access** via persistent_term
7. **Efficient caching** via ETS with TTL

The architecture follows OTP best practices and is designed to scale from single-node development to multi-node production clusters.
