# Pipeline Orchestration: Broadway, GenStage, and MLOps Patterns

**Expert:** Dr. Aisha Patel, Senior Fellow MLOps Engineer
**Experience:** 15+ years at Google ML Platform, Uber Michelangelo, Netflix ML Infrastructure

---

## Table of Contents

1. [Pipeline Architecture Overview](#pipeline-architecture-overview)
2. [Broadway Ingestion Pipelines](#broadway-ingestion-pipelines)
3. [Query Pipelines](#query-pipelines)
4. [Manifest-Driven Pipeline Definition](#manifest-driven-pipeline-definition)
5. [Observability Stack](#observability-stack)
6. [Cost Optimization](#cost-optimization)
7. [Testing Strategies](#testing-strategies)

---

## 1. Pipeline Architecture Overview

### 1.1 Pipeline Types

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         PIPELINE TYPES                                   │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  INGESTION PIPELINES (Batch/Stream)                                     │
│  ┌────────┐    ┌────────┐    ┌────────┐    ┌────────┐    ┌────────┐    │
│  │Discover│───▶│ Chunk  │───▶│ Embed  │───▶│ Store  │───▶│ Graph  │    │
│  │ Files  │    │Content │    │Chunks  │    │Vectors │    │Extract │    │
│  └────────┘    └────────┘    └────────┘    └────────┘    └────────┘    │
│                                                                          │
│  QUERY PIPELINES (Real-time)                                            │
│  ┌────────┐    ┌────────┐    ┌────────┐    ┌────────┐    ┌────────┐    │
│  │ Parse  │───▶│ Embed  │───▶│Retrieve│───▶│Rerank  │───▶│Generate│    │
│  │ Query  │    │ Query  │    │Chunks  │    │Results │    │Answer  │    │
│  └────────┘    └────────┘    └────────┘    └────────┘    └────────┘    │
│                                                                          │
│  EVALUATION PIPELINES (Periodic)                                        │
│  ┌────────┐    ┌────────┐    ┌────────┐    ┌────────┐                   │
│  │ Load   │───▶│ Run    │───▶│Compute │───▶│ Store  │                   │
│  │Test Set│    │Queries │    │Metrics │    │Results │                   │
│  └────────┘    └────────┘    └────────┘    └────────┘                   │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

### 1.2 Pipeline Execution Model

```elixir
defmodule PortfolioManager.Pipelines.Executor do
  @moduledoc """
  Core pipeline execution engine.
  """

  @type step :: %{
    name: atom(),
    module: module(),
    config: map(),
    retries: non_neg_integer(),
    timeout: non_neg_integer()
  }

  @type pipeline :: %{
    id: String.t(),
    steps: [step()],
    context: map()
  }

  @type execution_result :: %{
    pipeline_id: String.t(),
    status: :success | :partial | :failed,
    steps_completed: non_neg_integer(),
    duration_ms: non_neg_integer(),
    outputs: map(),
    errors: [map()]
  }

  @doc """
  Execute a pipeline with the given context.
  """
  @spec execute(pipeline(), map()) :: {:ok, execution_result()} | {:error, term()}
  def execute(pipeline, initial_context) do
    start_time = System.monotonic_time(:millisecond)

    result = Enum.reduce_while(pipeline.steps, {:ok, initial_context, []}, fn step, {:ok, ctx, completed} ->
      case execute_step(step, ctx) do
        {:ok, new_ctx} ->
          {:cont, {:ok, new_ctx, [step.name | completed]}}

        {:error, reason} ->
          {:halt, {:error, reason, completed}}
      end
    end)

    duration = System.monotonic_time(:millisecond) - start_time

    case result do
      {:ok, final_ctx, completed} ->
        {:ok, %{
          pipeline_id: pipeline.id,
          status: :success,
          steps_completed: length(completed),
          duration_ms: duration,
          outputs: final_ctx,
          errors: []
        }}

      {:error, reason, completed} ->
        {:ok, %{
          pipeline_id: pipeline.id,
          status: :failed,
          steps_completed: length(completed),
          duration_ms: duration,
          outputs: %{},
          errors: [reason]
        }}
    end
  end

  defp execute_step(step, context) do
    timeout = step[:timeout] || 30_000
    retries = step[:retries] || 0

    execute_with_retry(step, context, retries, timeout)
  end

  defp execute_with_retry(step, context, retries, timeout) do
    task = Task.async(fn ->
      step.module.execute(context, step.config)
    end)

    case Task.yield(task, timeout) || Task.shutdown(task) do
      {:ok, {:ok, _} = result} ->
        result

      {:ok, {:error, reason}} when retries > 0 ->
        Process.sleep(exponential_backoff(step[:retries] - retries))
        execute_with_retry(step, context, retries - 1, timeout)

      {:ok, {:error, _} = error} ->
        error

      nil ->
        if retries > 0 do
          execute_with_retry(step, context, retries - 1, timeout)
        else
          {:error, :timeout}
        end
    end
  end

  defp exponential_backoff(attempt) do
    trunc(:math.pow(2, attempt) * 100) + :rand.uniform(100)
  end
end
```

---

## 2. Broadway Ingestion Pipelines

### 2.1 Full Ingestion Pipeline

```elixir
defmodule PortfolioManager.Pipelines.Ingest.Broadway do
  @moduledoc """
  Broadway-based ingestion pipeline with backpressure and batching.
  """

  use Broadway

  alias Broadway.Message

  @impl true
  def start_link(opts) do
    pipeline_config = Keyword.fetch!(opts, :config)

    Broadway.start_link(__MODULE__,
      name: opts[:name] || __MODULE__,
      producer: [
        module: {PortfolioManager.Pipelines.Ingest.FileProducer, [
          repo_paths: pipeline_config[:repo_paths],
          file_patterns: pipeline_config[:file_patterns] || ["**/*.md", "**/*.ex"]
        ]},
        transformer: {__MODULE__, :transform, []},
        concurrency: 1
      ],
      processors: [
        default: [
          concurrency: pipeline_config[:processor_concurrency] || 4,
          min_demand: 1,
          max_demand: 10
        ]
      ],
      batchers: [
        embed: [
          concurrency: pipeline_config[:embed_concurrency] || 2,
          batch_size: pipeline_config[:embed_batch_size] || 50,
          batch_timeout: 2000
        ],
        store: [
          concurrency: pipeline_config[:store_concurrency] || 2,
          batch_size: pipeline_config[:store_batch_size] || 100,
          batch_timeout: 1000
        ]
      ],
      context: %{
        chunker: pipeline_config[:chunker],
        embedder: pipeline_config[:embedder],
        vector_store: pipeline_config[:vector_store],
        graph_store: pipeline_config[:graph_store],
        telemetry_prefix: [:portfolio, :ingest]
      }
    )
  end

  def transform(event, _opts) do
    %Message{
      data: event,
      acknowledger: {__MODULE__, :ack_id, :ack_data}
    }
  end

  @impl true
  def handle_message(_, %Message{data: file} = message, context) do
    :telemetry.span(
      context.telemetry_prefix ++ [:chunk],
      %{file: file.path},
      fn ->
        case context.chunker.chunk(file.content, strategy: detect_strategy(file)) do
          {:ok, chunks} ->
            # Fan out to multiple messages, one per chunk
            messages = Enum.map(chunks, fn chunk ->
              %{
                chunk: chunk,
                file: file,
                repo_id: file.repo_id
              }
            end)

            # Put all chunks to embed batcher
            {Message.put_batch_key(message, :embed)
             |> Message.put_data(messages), %{chunk_count: length(chunks)}}

          {:error, reason} ->
            {Message.failed(message, reason), %{error: reason}}
        end
      end
    )
  end

  @impl true
  def handle_batch(:embed, messages, batch_info, context) do
    :telemetry.span(
      context.telemetry_prefix ++ [:embed_batch],
      %{batch_size: length(messages)},
      fn ->
        # Flatten all chunks from all messages
        all_chunks = Enum.flat_map(messages, fn msg ->
          msg.data
        end)

        contents = Enum.map(all_chunks, & &1.chunk.content)

        case context.embedder.embed_batch(contents, []) do
          {:ok, embeddings} ->
            # Zip embeddings back to chunks
            embedded = Enum.zip(all_chunks, embeddings)
            |> Enum.map(fn {chunk_data, embedding} ->
              Map.put(chunk_data, :embedding, embedding)
            end)

            # Update messages with embedded data
            updated_messages = messages
            |> Enum.with_index()
            |> Enum.map(fn {msg, idx} ->
              chunk_count = length(msg.data)
              start_idx = Enum.sum(Enum.map(Enum.take(messages, idx), &length(&1.data)))
              embedded_chunks = Enum.slice(embedded, start_idx, chunk_count)

              msg
              |> Message.put_data(embedded_chunks)
              |> Message.put_batcher(:store)
            end)

            {updated_messages, %{embedded_count: length(embeddings)}}

          {:error, reason} ->
            failed = Enum.map(messages, &Message.failed(&1, reason))
            {failed, %{error: reason}}
        end
      end
    )
  end

  @impl true
  def handle_batch(:store, messages, _batch_info, context) do
    :telemetry.span(
      context.telemetry_prefix ++ [:store_batch],
      %{batch_size: length(messages)},
      fn ->
        all_chunks = Enum.flat_map(messages, & &1.data)

        vector_chunks = Enum.map(all_chunks, fn chunk_data ->
          %{
            content: chunk_data.chunk.content,
            embedding: chunk_data.embedding,
            metadata: %{
              repo_id: chunk_data.repo_id,
              path: chunk_data.file.path,
              chunk_index: chunk_data.chunk.index
            }
          }
        end)

        case context.vector_store.store_chunks(vector_chunks) do
          {:ok, chunk_ids} ->
            # Optionally extract entities for graph
            if context.graph_store do
              extract_and_store_entities(all_chunks, chunk_ids, context)
            end

            {messages, %{stored_count: length(chunk_ids)}}

          {:error, reason} ->
            failed = Enum.map(messages, &Message.failed(&1, reason))
            {failed, %{error: reason}}
        end
      end
    )
  end

  @impl true
  def handle_failed(messages, context) do
    Enum.each(messages, fn msg ->
      :telemetry.execute(
        context.telemetry_prefix ++ [:failed],
        %{count: 1},
        %{reason: msg.status, file: msg.data[:file][:path]}
      )
    end)

    messages
  end

  defp detect_strategy(file) do
    cond do
      String.ends_with?(file.path, ".ex") -> :code
      String.ends_with?(file.path, ".exs") -> :code
      String.ends_with?(file.path, ".py") -> :code
      String.ends_with?(file.path, ".js") -> :code
      String.ends_with?(file.path, ".ts") -> :code
      true -> :recursive
    end
  end

  defp extract_and_store_entities(chunks, chunk_ids, context) do
    # Entity extraction would happen here
    :ok
  end

  def ack_id, do: :ack_id
  def ack_data, do: :ack_data
end
```

### 2.2 File Producer

```elixir
defmodule PortfolioManager.Pipelines.Ingest.FileProducer do
  @moduledoc """
  Broadway producer that discovers and emits files for ingestion.
  """

  use GenStage

  defstruct [:repo_paths, :file_patterns, :file_queue, :seen_hashes]

  def start_link(opts) do
    GenStage.start_link(__MODULE__, opts)
  end

  @impl true
  def init(opts) do
    state = %__MODULE__{
      repo_paths: opts[:repo_paths] || [],
      file_patterns: opts[:file_patterns] || ["**/*"],
      file_queue: :queue.new(),
      seen_hashes: MapSet.new()
    }

    # Initial file discovery
    send(self(), :discover_files)

    {:producer, state}
  end

  @impl true
  def handle_demand(demand, state) when demand > 0 do
    {files, new_queue} = take_from_queue(state.file_queue, demand)
    {:noreply, files, %{state | file_queue: new_queue}}
  end

  @impl true
  def handle_info(:discover_files, state) do
    files = discover_files(state.repo_paths, state.file_patterns)

    # Filter out already seen files
    new_files = Enum.reject(files, fn file ->
      MapSet.member?(state.seen_hashes, file.content_hash)
    end)

    new_queue = Enum.reduce(new_files, state.file_queue, &:queue.in/2)
    new_seen = Enum.reduce(new_files, state.seen_hashes, fn file, acc ->
      MapSet.put(acc, file.content_hash)
    end)

    # Schedule next discovery
    Process.send_after(self(), :discover_files, 60_000)

    {:noreply, [], %{state | file_queue: new_queue, seen_hashes: new_seen}}
  end

  defp discover_files(repo_paths, patterns) do
    Enum.flat_map(repo_paths, fn repo_path ->
      Enum.flat_map(patterns, fn pattern ->
        Path.wildcard(Path.join(repo_path, pattern))
        |> Enum.map(fn path ->
          content = File.read!(path)
          %{
            path: path,
            repo_id: extract_repo_id(repo_path),
            content: content,
            content_hash: hash_content(content),
            discovered_at: DateTime.utc_now()
          }
        end)
      end)
    end)
  end

  defp take_from_queue(queue, count) do
    take_from_queue(queue, count, [])
  end

  defp take_from_queue(queue, 0, acc), do: {Enum.reverse(acc), queue}
  defp take_from_queue(queue, count, acc) do
    case :queue.out(queue) do
      {{:value, item}, rest} -> take_from_queue(rest, count - 1, [item | acc])
      {:empty, queue} -> {Enum.reverse(acc), queue}
    end
  end

  defp extract_repo_id(path) do
    path |> Path.basename()
  end

  defp hash_content(content) do
    :crypto.hash(:sha256, content) |> Base.encode16(case: :lower)
  end
end
```

### 2.3 Rate-Limited Embedding Batcher

```elixir
defmodule PortfolioManager.Pipelines.Ingest.RateLimitedBatcher do
  @moduledoc """
  Custom batcher that respects API rate limits for embedding providers.
  """

  use GenServer

  defstruct [
    :max_requests_per_minute,
    :max_tokens_per_minute,
    :current_requests,
    :current_tokens,
    :window_start,
    pending: :queue.new()
  ]

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: opts[:name])
  end

  @impl true
  def init(opts) do
    state = %__MODULE__{
      max_requests_per_minute: opts[:max_requests_per_minute] || 100,
      max_tokens_per_minute: opts[:max_tokens_per_minute] || 100_000,
      current_requests: 0,
      current_tokens: 0,
      window_start: System.monotonic_time(:millisecond)
    }

    schedule_window_reset()
    {:ok, state}
  end

  def embed_batch(batcher, contents) do
    GenServer.call(batcher, {:embed_batch, contents}, 60_000)
  end

  @impl true
  def handle_call({:embed_batch, contents}, from, state) do
    estimated_tokens = estimate_tokens(contents)
    state = maybe_reset_window(state)

    if can_process?(state, estimated_tokens) do
      # Process immediately
      result = do_embed(contents)
      new_state = %{state |
        current_requests: state.current_requests + 1,
        current_tokens: state.current_tokens + estimated_tokens
      }
      {:reply, result, new_state}
    else
      # Queue for later
      new_pending = :queue.in({from, contents, estimated_tokens}, state.pending)
      {:noreply, %{state | pending: new_pending}}
    end
  end

  @impl true
  def handle_info(:process_pending, state) do
    state = maybe_reset_window(state)
    state = process_pending_requests(state)
    schedule_pending_check()
    {:noreply, state}
  end

  @impl true
  def handle_info(:reset_window, state) do
    new_state = %{state |
      current_requests: 0,
      current_tokens: 0,
      window_start: System.monotonic_time(:millisecond)
    }
    schedule_window_reset()
    {:noreply, process_pending_requests(new_state)}
  end

  defp maybe_reset_window(state) do
    now = System.monotonic_time(:millisecond)
    if now - state.window_start > 60_000 do
      %{state |
        current_requests: 0,
        current_tokens: 0,
        window_start: now
      }
    else
      state
    end
  end

  defp can_process?(state, tokens) do
    state.current_requests < state.max_requests_per_minute and
      state.current_tokens + tokens < state.max_tokens_per_minute
  end

  defp process_pending_requests(state) do
    case :queue.out(state.pending) do
      {{:value, {from, contents, tokens}}, rest} ->
        if can_process?(state, tokens) do
          result = do_embed(contents)
          GenServer.reply(from, result)

          new_state = %{state |
            pending: rest,
            current_requests: state.current_requests + 1,
            current_tokens: state.current_tokens + tokens
          }

          process_pending_requests(new_state)
        else
          state
        end

      {:empty, _} ->
        state
    end
  end

  defp do_embed(contents) do
    # Call actual embedding API
    {:ok, Enum.map(contents, fn _ -> [] end)}
  end

  defp estimate_tokens(contents) do
    # Rough estimate: 1 token ≈ 4 characters
    contents
    |> Enum.map(&String.length/1)
    |> Enum.sum()
    |> div(4)
  end

  defp schedule_window_reset do
    Process.send_after(self(), :reset_window, 60_000)
  end

  defp schedule_pending_check do
    Process.send_after(self(), :process_pending, 1000)
  end
end
```

---

## 3. Query Pipelines

### 3.1 Query Pipeline Implementation

```elixir
defmodule PortfolioManager.Pipelines.Query do
  @moduledoc """
  Real-time query pipeline for RAG retrieval.
  """

  alias PortfolioManager.Pipelines.Executor

  @doc """
  Execute a query through the RAG pipeline.
  """
  def execute(query, opts \\ []) do
    pipeline = build_pipeline(opts)
    context = %{
      query: query,
      opts: opts,
      trace_id: generate_trace_id()
    }

    Executor.execute(pipeline, context)
  end

  defp build_pipeline(opts) do
    mode = Keyword.get(opts, :mode, :hybrid)

    base_steps = [
      %{name: :parse_query, module: Steps.ParseQuery, config: %{}},
      %{name: :embed_query, module: Steps.EmbedQuery, config: %{}, retries: 2}
    ]

    retrieval_steps = case mode do
      :semantic -> [
        %{name: :vector_search, module: Steps.VectorSearch, config: opts}
      ]

      :graph -> [
        %{name: :graph_search, module: Steps.GraphSearch, config: opts}
      ]

      :hybrid -> [
        %{name: :vector_search, module: Steps.VectorSearch, config: opts},
        %{name: :graph_expand, module: Steps.GraphExpand, config: opts},
        %{name: :merge_results, module: Steps.MergeResults, config: opts}
      ]
    end

    post_steps = [
      %{name: :rerank, module: Steps.Rerank, config: opts, retries: 1},
      %{name: :build_context, module: Steps.BuildContext, config: opts}
    ]

    generation_steps = if Keyword.get(opts, :generate, true) do
      [%{name: :generate_answer, module: Steps.GenerateAnswer, config: opts, retries: 2}]
    else
      []
    end

    %{
      id: generate_pipeline_id(),
      steps: base_steps ++ retrieval_steps ++ post_steps ++ generation_steps,
      context: %{}
    }
  end

  defp generate_trace_id do
    :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
  end

  defp generate_pipeline_id do
    "query_#{System.system_time(:millisecond)}_#{:rand.uniform(10000)}"
  end
end

defmodule PortfolioManager.Pipelines.Query.Steps.VectorSearch do
  @behaviour PortfolioManager.Pipelines.Step

  @impl true
  def execute(context, config) do
    limit = config[:limit] || 20
    index_id = config[:index_id]

    with {:ok, results} <- search(context.query_embedding, limit, index_id) do
      {:ok, Map.put(context, :vector_results, results)}
    end
  end

  defp search(embedding, limit, index_id) do
    # Call vector store
    {:ok, []}
  end
end

defmodule PortfolioManager.Pipelines.Query.Steps.GraphExpand do
  @behaviour PortfolioManager.Pipelines.Step

  @impl true
  def execute(context, config) do
    depth = config[:expansion_depth] || 2
    vector_results = context.vector_results

    # Find entities mentioned in retrieved chunks
    entities = extract_entities(vector_results)

    # Expand via graph traversal
    expanded = Enum.flat_map(entities, fn entity ->
      case traverse(entity, depth) do
        {:ok, neighbors} -> neighbors
        _ -> []
      end
    end)

    {:ok, Map.put(context, :graph_results, expanded)}
  end

  defp extract_entities(_results), do: []
  defp traverse(_entity, _depth), do: {:ok, []}
end

defmodule PortfolioManager.Pipelines.Query.Steps.Rerank do
  @behaviour PortfolioManager.Pipelines.Step

  @impl true
  def execute(context, config) do
    limit = config[:final_limit] || 10
    reranker = config[:reranker] || :cross_encoder

    all_results = (context[:vector_results] || []) ++ (context[:graph_results] || [])

    reranked = case reranker do
      :cross_encoder -> cross_encoder_rerank(context.query, all_results)
      :llm -> llm_rerank(context.query, all_results)
      :rrf -> rrf_rerank(all_results)
    end

    {:ok, Map.put(context, :reranked_results, Enum.take(reranked, limit))}
  end

  defp cross_encoder_rerank(_query, results), do: results
  defp llm_rerank(_query, results), do: results
  defp rrf_rerank(results), do: results
end
```

---

## 4. Manifest-Driven Pipeline Definition

### 4.1 Pipeline YAML Schema

```yaml
pipelines:
  # Ingestion pipeline for documents
  ingest_docs:
    type: broadway
    producer:
      module: file_producer
      config:
        patterns: ["**/*.md", "**/*.txt"]
        watch: true
    processors:
      default:
        concurrency: 4
        max_demand: 10
    batchers:
      embed:
        batch_size: 50
        batch_timeout: 2000
        concurrency: 2
      store:
        batch_size: 100
        batch_timeout: 1000
        concurrency: 2
    steps:
      - name: chunk
        uses_port: chunker
        config:
          strategy: recursive
          chunk_size: 1000
      - name: embed
        uses_port: embedder
        config:
          model: text-embedding-3-small
      - name: store
        uses_port: vector_store
      - name: extract_entities
        module: entity_extractor
        condition: feature_flag.graph_rag_enabled
      - name: store_graph
        uses_port: graph_store
        condition: feature_flag.graph_rag_enabled

  # Query pipeline
  query_hybrid:
    type: sequential
    timeout: 30000
    steps:
      - name: parse
        module: query_parser
      - name: embed
        uses_port: embedder
        retries: 2
      - name: vector_search
        uses_port: vector_store
        config:
          limit: 20
      - name: graph_expand
        uses_port: graph_store
        config:
          depth: 2
        condition: opts.mode == :hybrid
      - name: rerank
        module: reranker
        config:
          method: cross_encoder
          limit: 10
      - name: generate
        uses_port: llm
        condition: opts.generate
        retries: 2
```

### 4.2 Pipeline Builder from Manifest

```elixir
defmodule PortfolioManager.Pipelines.Builder do
  @moduledoc """
  Build pipeline specifications from manifest definitions.
  """

  def build_from_manifest(manifest, pipeline_name) do
    pipeline_config = get_in(manifest, [:pipelines, pipeline_name])

    case pipeline_config[:type] do
      :broadway -> build_broadway_pipeline(pipeline_config)
      :sequential -> build_sequential_pipeline(pipeline_config)
      :parallel -> build_parallel_pipeline(pipeline_config)
    end
  end

  defp build_broadway_pipeline(config) do
    %{
      type: :broadway,
      module: PortfolioManager.Pipelines.Ingest.Broadway,
      opts: [
        config: %{
          processor_concurrency: get_in(config, [:processors, :default, :concurrency]) || 4,
          embed_batch_size: get_in(config, [:batchers, :embed, :batch_size]) || 50,
          embed_concurrency: get_in(config, [:batchers, :embed, :concurrency]) || 2,
          store_batch_size: get_in(config, [:batchers, :store, :batch_size]) || 100,
          store_concurrency: get_in(config, [:batchers, :store, :concurrency]) || 2,
          steps: build_steps(config[:steps])
        }
      ]
    }
  end

  defp build_sequential_pipeline(config) do
    %{
      type: :sequential,
      timeout: config[:timeout] || 30_000,
      steps: build_steps(config[:steps])
    }
  end

  defp build_parallel_pipeline(config) do
    %{
      type: :parallel,
      timeout: config[:timeout] || 30_000,
      branches: Enum.map(config[:branches], &build_steps/1)
    }
  end

  defp build_steps(steps_config) do
    Enum.map(steps_config, fn step ->
      %{
        name: String.to_atom(step[:name]),
        module: resolve_step_module(step),
        config: step[:config] || %{},
        retries: step[:retries] || 0,
        condition: step[:condition]
      }
    end)
  end

  defp resolve_step_module(%{module: module_name}) do
    Module.concat([PortfolioManager.Pipelines.Steps, Macro.camelize(module_name)])
  end

  defp resolve_step_module(%{uses_port: port_name}) do
    # Steps that use ports get a generic port-calling step
    Module.concat([PortfolioManager.Pipelines.Steps.PortStep])
  end
end
```

---

## 5. Observability Stack

### 5.1 Telemetry Integration

```elixir
defmodule PortfolioManager.Telemetry do
  use Supervisor

  def start_link(arg) do
    Supervisor.start_link(__MODULE__, arg, name: __MODULE__)
  end

  @impl true
  def init(_arg) do
    children = [
      {TelemetryMetricsPrometheus, metrics: metrics()},
      {PortfolioManager.Telemetry.SpanReporter, []}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  defp metrics do
    [
      # Pipeline metrics
      counter("portfolio.ingest.chunk.count"),
      counter("portfolio.ingest.embed_batch.count"),
      counter("portfolio.ingest.store_batch.count"),
      counter("portfolio.ingest.failed.count"),

      summary("portfolio.ingest.chunk.duration",
        unit: {:native, :millisecond}
      ),
      summary("portfolio.ingest.embed_batch.duration",
        unit: {:native, :millisecond}
      ),

      # Query metrics
      counter("portfolio.query.count"),
      summary("portfolio.query.duration",
        unit: {:native, :millisecond}
      ),
      distribution("portfolio.query.result_count"),

      # Vector store metrics
      counter("portfolio.vector.search.count"),
      summary("portfolio.vector.search.duration",
        unit: {:native, :millisecond}
      ),
      distribution("portfolio.vector.search.result_count"),

      # Graph store metrics
      counter("portfolio.graph.traverse.count"),
      summary("portfolio.graph.traverse.duration",
        unit: {:native, :millisecond}
      ),

      # Embedder metrics
      counter("portfolio.embedder.tokens_used"),
      summary("portfolio.embedder.batch_size"),
      summary("portfolio.embedder.duration",
        unit: {:native, :millisecond}
      ),

      # Cost tracking
      counter("portfolio.cost.embedding_tokens"),
      counter("portfolio.cost.llm_tokens"),
      sum("portfolio.cost.usd",
        unit: :dollar
      )
    ]
  end
end

defmodule PortfolioManager.Telemetry.SpanReporter do
  @moduledoc """
  OpenTelemetry span reporter for distributed tracing.
  """

  use GenServer

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    :telemetry.attach_many(
      "portfolio-spans",
      [
        [:portfolio, :ingest, :chunk, :start],
        [:portfolio, :ingest, :chunk, :stop],
        [:portfolio, :ingest, :embed_batch, :start],
        [:portfolio, :ingest, :embed_batch, :stop],
        [:portfolio, :query, :start],
        [:portfolio, :query, :stop]
      ],
      &handle_event/4,
      nil
    )

    {:ok, %{}}
  end

  def handle_event(event, measurements, metadata, _config) do
    # Convert to OpenTelemetry spans
    # This would integrate with your OTel collector
    :ok
  end
end
```

### 5.2 Cost Tracking

```elixir
defmodule PortfolioManager.CostTracker do
  @moduledoc """
  Track API costs for embeddings and LLM calls.
  """

  use GenServer

  @embedding_costs %{
    "text-embedding-3-small" => 0.00002,  # per 1K tokens
    "text-embedding-3-large" => 0.00013,
    "voyage-code-2" => 0.0001
  }

  @llm_costs %{
    "gpt-4o" => %{input: 0.0025, output: 0.01},  # per 1K tokens
    "claude-3-sonnet" => %{input: 0.003, output: 0.015},
    "gemini-flash-lite-latest" => %{input: 0.00125, output: 0.005}
  }

  defstruct [
    :daily_budget,
    :current_spend,
    :spend_by_operation,
    :window_start
  ]

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(opts) do
    state = %__MODULE__{
      daily_budget: opts[:daily_budget] || 100.0,
      current_spend: 0.0,
      spend_by_operation: %{},
      window_start: Date.utc_today()
    }

    {:ok, state}
  end

  def track_embedding(model, token_count) do
    GenServer.cast(__MODULE__, {:embedding, model, token_count})
  end

  def track_llm(model, input_tokens, output_tokens) do
    GenServer.cast(__MODULE__, {:llm, model, input_tokens, output_tokens})
  end

  def get_spend_report do
    GenServer.call(__MODULE__, :report)
  end

  def check_budget do
    GenServer.call(__MODULE__, :check_budget)
  end

  @impl true
  def handle_cast({:embedding, model, tokens}, state) do
    cost = calculate_embedding_cost(model, tokens)
    new_state = add_cost(state, :embedding, cost)

    emit_cost_telemetry(:embedding, cost, model)

    {:noreply, new_state}
  end

  def handle_cast({:llm, model, input_tokens, output_tokens}, state) do
    cost = calculate_llm_cost(model, input_tokens, output_tokens)
    new_state = add_cost(state, :llm, cost)

    emit_cost_telemetry(:llm, cost, model)

    {:noreply, new_state}
  end

  @impl true
  def handle_call(:report, _from, state) do
    report = %{
      current_spend: state.current_spend,
      daily_budget: state.daily_budget,
      remaining: state.daily_budget - state.current_spend,
      by_operation: state.spend_by_operation,
      window_start: state.window_start
    }

    {:reply, report, state}
  end

  def handle_call(:check_budget, _from, state) do
    remaining = state.daily_budget - state.current_spend
    {:reply, {:ok, remaining > 0, remaining}, state}
  end

  defp calculate_embedding_cost(model, tokens) do
    rate = Map.get(@embedding_costs, model, 0.0001)
    tokens / 1000 * rate
  end

  defp calculate_llm_cost(model, input_tokens, output_tokens) do
    rates = Map.get(@llm_costs, model, %{input: 0.01, output: 0.03})
    input_tokens / 1000 * rates.input + output_tokens / 1000 * rates.output
  end

  defp add_cost(state, operation, cost) do
    new_spend = state.current_spend + cost
    new_by_op = Map.update(state.spend_by_operation, operation, cost, &(&1 + cost))

    %{state | current_spend: new_spend, spend_by_operation: new_by_op}
  end

  defp emit_cost_telemetry(operation, cost, model) do
    :telemetry.execute(
      [:portfolio, :cost, :usd],
      %{amount: cost},
      %{operation: operation, model: model}
    )
  end
end
```

---

## 6. Cost Optimization

### 6.1 Caching Strategy

```elixir
defmodule PortfolioManager.Cache.EmbeddingCache do
  @moduledoc """
  Cache embeddings to avoid redundant API calls.
  """

  use GenServer

  @table :embedding_cache
  @max_size 100_000
  @ttl_ms 86_400_000  # 24 hours

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    :ets.new(@table, [:set, :public, :named_table, read_concurrency: true])
    schedule_cleanup()
    {:ok, %{}}
  end

  def get_or_embed(content, embedder, opts \\ []) do
    key = cache_key(content, opts[:model])

    case :ets.lookup(@table, key) do
      [{^key, embedding, expires_at}] when expires_at > System.monotonic_time(:millisecond) ->
        :telemetry.execute([:portfolio, :cache, :hit], %{count: 1}, %{type: :embedding})
        {:ok, embedding}

      _ ->
        :telemetry.execute([:portfolio, :cache, :miss], %{count: 1}, %{type: :embedding})

        case embedder.embed(content, opts) do
          {:ok, embedding} = result ->
            expires_at = System.monotonic_time(:millisecond) + @ttl_ms
            :ets.insert(@table, {key, embedding, expires_at})
            result

          error ->
            error
        end
    end
  end

  def get_or_embed_batch(contents, embedder, opts \\ []) do
    model = opts[:model]

    # Check cache for each content
    {cached, uncached} = Enum.split_with(contents, fn content ->
      key = cache_key(content, model)
      case :ets.lookup(@table, key) do
        [{^key, _, expires_at}] when expires_at > System.monotonic_time(:millisecond) -> true
        _ -> false
      end
    end)

    # Get cached embeddings
    cached_embeddings = Enum.map(cached, fn content ->
      [{_, embedding, _}] = :ets.lookup(@table, cache_key(content, model))
      embedding
    end)

    # Embed uncached
    if uncached == [] do
      {:ok, cached_embeddings}
    else
      case embedder.embed_batch(uncached, opts) do
        {:ok, new_embeddings} ->
          # Cache new embeddings
          Enum.zip(uncached, new_embeddings)
          |> Enum.each(fn {content, embedding} ->
            key = cache_key(content, model)
            expires_at = System.monotonic_time(:millisecond) + @ttl_ms
            :ets.insert(@table, {key, embedding, expires_at})
          end)

          # Merge results in original order
          {:ok, merge_in_order(contents, cached_embeddings, uncached, new_embeddings, model)}

        error ->
          error
      end
    end
  end

  defp cache_key(content, model) do
    hash = :crypto.hash(:sha256, content) |> Base.encode16(case: :lower)
    {model || :default, hash}
  end

  defp merge_in_order(original, cached, uncached, new_embeddings, model) do
    uncached_map = Enum.zip(uncached, new_embeddings) |> Map.new()

    Enum.map(original, fn content ->
      key = cache_key(content, model)
      case :ets.lookup(@table, key) do
        [{^key, embedding, _}] -> embedding
        _ -> Map.get(uncached_map, content)
      end
    end)
  end

  @impl true
  def handle_info(:cleanup, state) do
    now = System.monotonic_time(:millisecond)

    # Delete expired entries
    :ets.select_delete(@table, [
      {{:_, :_, :"$1"}, [{:<, :"$1", now}], [true]}
    ])

    # If still over max size, evict oldest
    if :ets.info(@table, :size) > @max_size do
      evict_oldest(@max_size * 0.9)
    end

    schedule_cleanup()
    {:noreply, state}
  end

  defp schedule_cleanup do
    Process.send_after(self(), :cleanup, 60_000)
  end

  defp evict_oldest(target_size) do
    # Simple LRU-ish eviction
    all = :ets.tab2list(@table)
    sorted = Enum.sort_by(all, fn {_, _, expires_at} -> expires_at end)
    to_delete = length(sorted) - trunc(target_size)

    sorted
    |> Enum.take(to_delete)
    |> Enum.each(fn {key, _, _} -> :ets.delete(@table, key) end)
  end
end
```

---

## 7. Testing Strategies

### 7.1 Pipeline Testing

```elixir
defmodule PortfolioManager.Pipelines.IngestTest do
  use ExUnit.Case, async: true

  alias PortfolioManager.Pipelines.Ingest.Broadway, as: IngestPipeline

  describe "ingestion pipeline" do
    setup do
      # Start pipeline with mock adapters
      {:ok, pid} = IngestPipeline.start_link(
        name: :test_ingest,
        config: %{
          repo_paths: ["test/fixtures/repos"],
          chunker: MockChunker,
          embedder: MockEmbedder,
          vector_store: MockVectorStore,
          graph_store: nil
        }
      )

      on_exit(fn -> GenServer.stop(pid) end)

      {:ok, pipeline: pid}
    end

    test "processes files through all stages", %{pipeline: pipeline} do
      # Wait for initial file discovery and processing
      Process.sleep(1000)

      # Check that chunks were stored
      assert MockVectorStore.stored_count() > 0
    end

    test "handles chunker failures gracefully" do
      MockChunker.set_failure_mode(true)

      # Process should not crash
      {:ok, pid} = IngestPipeline.start_link(
        name: :test_ingest_fail,
        config: %{
          repo_paths: ["test/fixtures/failing"],
          chunker: MockChunker,
          embedder: MockEmbedder,
          vector_store: MockVectorStore
        }
      )

      Process.sleep(500)
      assert Process.alive?(pid)
    end

    test "respects rate limits for embedding" do
      start_time = System.monotonic_time(:millisecond)

      # Process 200 files (should hit rate limit)
      # ...

      duration = System.monotonic_time(:millisecond) - start_time

      # Should have waited due to rate limiting
      assert duration > 1000
    end
  end
end

defmodule MockChunker do
  @behaviour PortfolioCore.Ports.ChunkerPort

  @failure_mode false

  def set_failure_mode(mode), do: :persistent_term.put(:chunker_fail, mode)

  @impl true
  def chunk(content, _opts) do
    if :persistent_term.get(:chunker_fail, false) do
      {:error, :simulated_failure}
    else
      chunks = content
      |> String.split("\n\n")
      |> Enum.with_index()
      |> Enum.map(fn {text, idx} ->
        %{content: text, index: idx, start_offset: 0, end_offset: String.length(text), metadata: %{}}
      end)

      {:ok, chunks}
    end
  end

  @impl true
  def list_strategies, do: [:test]

  @impl true
  def strategy_info(_), do: {:ok, %{}}

  @impl true
  def estimate_chunks(content, _opts), do: {:ok, div(String.length(content), 100)}
end
```

---

## Summary

This pipeline architecture provides:

1. **Broadway Pipelines**: Backpressure, batching, and failure isolation
2. **Rate Limiting**: Respect API quotas for embedding providers
3. **Manifest-Driven**: Configure pipelines via YAML
4. **Full Observability**: Telemetry, tracing, and cost tracking
5. **Caching**: Reduce redundant API calls
6. **Testing**: Comprehensive pipeline testing strategies

The architecture handles both batch ingestion and real-time queries with proper error handling and cost management.
