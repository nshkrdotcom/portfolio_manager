# Portfolio Manager v0.3.0 Implementation Prompt

## Mission

Implement Router module for multi-provider LLM support, streaming responses, Agent framework with tools, and Pipeline orchestration. Use TDD. All tests passing, no warnings, no dialyzer errors, credo --strict clean.

**Note:** This implementation depends on:
- portfolio_core v0.2.0 (new ports)
- portfolio_index v0.2.0 (LLM adapters using claude_agent_sdk and codex_sdk)

The LLM adapters in portfolio_index use SDK wrappers and default models unless overridden.

---

## Required Reading

### Documentation (Read First)
```
docs/20251227/ecosystem_expansion/00_ecosystem_overview.md
docs/20251227/ecosystem_expansion/01_current_state.md
docs/20251227/ecosystem_expansion/02_expansion_roadmap.md
docs/20251227/ecosystem_expansion/03_implementation_details.md
docs/20251226/expert_architecture_review/00_executive_summary.md
```

### Source Files - Core Modules
```
lib/portfolio_manager.ex
lib/portfolio_manager/application.ex
lib/portfolio_manager/rag.ex
lib/portfolio_manager/graph.ex
lib/portfolio_manager/domain/registry.ex
lib/portfolio_manager/repo.ex
```

### Source Files - CLI Tasks
```
lib/mix/tasks/portfolio.ask.ex
lib/mix/tasks/portfolio.search.ex
lib/mix/tasks/portfolio.index.ex
lib/mix/tasks/portfolio.graph.ex
```

### Configuration
```
mix.exs
config/config.exs
config/manifests/development.yml
config/manifests/test.yml
config/manifests/production.yml
README.md
CHANGELOG.md
```

### Test Files
```
test/test_helper.exs
test/support/mocks.ex
test/rag_test.exs
test/graph_test.exs
```

### Guides
```
guides/getting_started.md
guides/rag.md
guides/graph.md
guides/configuration.md
guides/cli.md
```

### Examples
```
examples/README.md
examples/run_all.sh
examples/rag_query.exs
examples/index_repo.exs
examples/graph_analysis.exs
examples/full_workflow.exs
```

---

## Implementation Tasks

### Task 1: Router Module

Create `lib/portfolio_manager/router.ex`:

```elixir
defmodule PortfolioManager.Router do
  @moduledoc """
  Multi-provider LLM routing with configurable strategies.

  Supports:
  - `:fallback` - Try providers in priority order
  - `:round_robin` - Distribute across healthy providers
  - `:specialist` - Route by task type and capabilities
  - `:cost_optimized` - Minimize cost while meeting requirements

  ## Configuration

  Configure in manifest:

      router:
        strategy: specialist
        health_check_interval: 30000
        providers:
          - name: gemini
            module: PortfolioIndex.Adapters.LLM.Gemini
            config:
              model: gemini-2.0-flash-exp
            capabilities: [generation, code, reasoning]
            priority: 1

          # Uses claude_agent_sdk - defaults to SDK default model
          - name: claude
            module: PortfolioIndex.Adapters.LLM.Anthropic
            config: {}
            capabilities: [reasoning, analysis]
            priority: 2

          # Uses codex_sdk - defaults to SDK default model
          - name: openai
            module: PortfolioIndex.Adapters.LLM.OpenAI
            config: {}
            capabilities: [generation, code]
            priority: 3

  ## Usage

      # Route automatically
      {:ok, response} = PortfolioManager.Router.complete(messages)

      # Force strategy
      {:ok, response} = PortfolioManager.Router.complete(messages, strategy: :fallback)

      # Specify task type for specialist routing
      {:ok, response} = PortfolioManager.Router.complete(messages, task_type: :code)

      # Stream response
      PortfolioManager.Router.stream(messages, fn chunk -> IO.write(chunk) end)
  """

  use GenServer

  require Logger

  alias PortfolioCore.Registry, as: CoreRegistry

  @type strategy :: :fallback | :round_robin | :specialist | :cost_optimized

  @type provider :: %{
    name: atom(),
    module: module(),
    config: map(),
    capabilities: [atom()],
    priority: non_neg_integer(),
    healthy: boolean(),
    last_check: DateTime.t() | nil
  }

  @default_strategy :fallback
  @health_check_interval 30_000

  # Client API

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Complete a request using the configured routing strategy.
  """
  @spec complete([map()], keyword()) :: {:ok, map()} | {:error, term()}
  def complete(messages, opts \\ []) do
    strategy = Keyword.get(opts, :strategy, get_strategy())
    task_type = Keyword.get(opts, :task_type)

    with {:ok, provider} <- select_provider(strategy, task_type),
         {:ok, response} <- call_provider(provider, :complete, [messages, opts]) do
      {:ok, response}
    end
  end

  @doc """
  Stream a response, calling the callback for each chunk.
  """
  @spec stream([map()], (String.t() -> any()), keyword()) :: :ok | {:error, term()}
  def stream(messages, callback, opts \\ []) when is_function(callback, 1) do
    strategy = Keyword.get(opts, :strategy, get_strategy())
    task_type = Keyword.get(opts, :task_type)

    with {:ok, provider} <- select_provider(strategy, task_type) do
      call_provider(provider, :stream, [messages, callback, opts])
    end
  end

  @doc """
  Register a new provider.
  """
  @spec register_provider(map()) :: :ok | {:error, term()}
  def register_provider(provider) do
    GenServer.call(__MODULE__, {:register_provider, provider})
  end

  @doc """
  List all registered providers.
  """
  @spec list_providers() :: [provider()]
  def list_providers do
    GenServer.call(__MODULE__, :list_providers)
  end

  @doc """
  Check health of a specific provider.
  """
  @spec health_check(atom()) :: :healthy | :unhealthy | :unknown
  def health_check(name) do
    GenServer.call(__MODULE__, {:health_check, name})
  end

  @doc """
  Get current routing strategy.
  """
  @spec get_strategy() :: strategy()
  def get_strategy do
    GenServer.call(__MODULE__, :get_strategy)
  end

  @doc """
  Set routing strategy.
  """
  @spec set_strategy(strategy()) :: :ok
  def set_strategy(strategy) do
    GenServer.call(__MODULE__, {:set_strategy, strategy})
  end

  # Server Callbacks

  @impl true
  def init(opts) do
    strategy = Keyword.get(opts, :strategy, @default_strategy)
    providers = Keyword.get(opts, :providers, [])
    health_interval = Keyword.get(opts, :health_check_interval, @health_check_interval)

    state = %{
      strategy: strategy,
      providers: initialize_providers(providers),
      round_robin_index: 0,
      health_check_interval: health_interval
    }

    # Schedule first health check
    if health_interval > 0 do
      Process.send_after(self(), :health_check, health_interval)
    end

    {:ok, state}
  end

  @impl true
  def handle_call({:register_provider, provider}, _from, state) do
    new_provider = Map.merge(provider, %{healthy: true, last_check: nil})
    new_providers = state.providers ++ [new_provider]
    {:reply, :ok, %{state | providers: new_providers}}
  end

  @impl true
  def handle_call(:list_providers, _from, state) do
    {:reply, state.providers, state}
  end

  @impl true
  def handle_call({:health_check, name}, _from, state) do
    status = case Enum.find(state.providers, &(&1.name == name)) do
      nil -> :unknown
      provider -> if provider.healthy, do: :healthy, else: :unhealthy
    end
    {:reply, status, state}
  end

  @impl true
  def handle_call(:get_strategy, _from, state) do
    {:reply, state.strategy, state}
  end

  @impl true
  def handle_call({:set_strategy, strategy}, _from, state) do
    {:reply, :ok, %{state | strategy: strategy}}
  end

  @impl true
  def handle_call({:select_provider, strategy, task_type}, _from, state) do
    {result, new_state} = do_select_provider(strategy, task_type, state)
    {:reply, result, new_state}
  end

  @impl true
  def handle_info(:health_check, state) do
    new_providers = Enum.map(state.providers, &check_provider_health/1)
    Process.send_after(self(), :health_check, state.health_check_interval)
    {:noreply, %{state | providers: new_providers}}
  end

  # Private Functions

  defp initialize_providers(providers) do
    Enum.map(providers, fn p ->
      Map.merge(p, %{healthy: true, last_check: nil})
    end)
  end

  defp select_provider(strategy, task_type) do
    GenServer.call(__MODULE__, {:select_provider, strategy, task_type})
  end

  defp do_select_provider(:fallback, _task_type, state) do
    case Enum.find(state.providers, & &1.healthy) do
      nil -> {{:error, :no_healthy_providers}, state}
      provider -> {{:ok, provider}, state}
    end
  end

  defp do_select_provider(:round_robin, _task_type, state) do
    healthy = Enum.filter(state.providers, & &1.healthy)

    case healthy do
      [] ->
        {{:error, :no_healthy_providers}, state}

      providers ->
        index = rem(state.round_robin_index, length(providers))
        provider = Enum.at(providers, index)
        new_state = %{state | round_robin_index: state.round_robin_index + 1}
        {{:ok, provider}, new_state}
    end
  end

  defp do_select_provider(:specialist, task_type, state) do
    matching =
      state.providers
      |> Enum.filter(& &1.healthy)
      |> Enum.filter(fn p ->
        task_type == nil or task_type in (p.capabilities || [])
      end)
      |> Enum.sort_by(& &1.priority)

    case matching do
      [] -> {{:error, :no_matching_providers}, state}
      [provider | _] -> {{:ok, provider}, state}
    end
  end

  defp do_select_provider(:cost_optimized, task_type, state) do
    matching =
      state.providers
      |> Enum.filter(& &1.healthy)
      |> Enum.filter(fn p ->
        task_type == nil or task_type in (p.capabilities || [])
      end)
      |> Enum.sort_by(& &1[:cost_per_token] || 0)

    case matching do
      [] -> {{:error, :no_matching_providers}, state}
      [provider | _] -> {{:ok, provider}, state}
    end
  end

  defp call_provider(provider, function, args) do
    apply(provider.module, function, args ++ [provider.config])
  rescue
    e ->
      Logger.error("Provider #{provider.name} failed: #{inspect(e)}")
      {:error, {:provider_error, provider.name, e}}
  end

  defp check_provider_health(provider) do
    healthy =
      case apply(provider.module, :model_info, [provider.config[:model]]) do
        {:ok, _} -> true
        _ -> false
      end

    %{provider | healthy: healthy, last_check: DateTime.utc_now()}
  rescue
    _ -> %{provider | healthy: false, last_check: DateTime.utc_now()}
  end
end
```

### Task 2: Streaming Support in RAG

Update `lib/portfolio_manager/rag.ex` to add streaming:

```elixir
# Add to existing module

@doc """
Stream a RAG query response.

Retrieves context synchronously, then streams the LLM response.

## Example

    PortfolioManager.RAG.stream_query("How does this work?", fn chunk ->
      IO.write(chunk)
    end)
"""
@spec stream_query(String.t(), (String.t() -> any()), keyword()) :: :ok | {:error, term()}
def stream_query(question, callback, opts \\ []) when is_function(callback, 1) do
  strategy = Keyword.get(opts, :strategy, :hybrid)
  top_k = Keyword.get(opts, :top_k, 5)

  with {:ok, context} <- retrieve(question, strategy, top_k),
       prompt <- build_prompt(question, context) do
    PortfolioManager.Router.stream(
      [%{role: :user, content: prompt}],
      callback,
      opts
    )
  end
end

@doc """
Stream search results as they are found.
"""
@spec stream_search(String.t(), (map() -> any()), keyword()) :: :ok | {:error, term()}
def stream_search(query, callback, opts \\ []) when is_function(callback, 1) do
  limit = Keyword.get(opts, :limit, 10)

  Task.async_stream(
    get_search_shards(),
    fn shard -> search_shard(shard, query, opts) end,
    max_concurrency: 4,
    ordered: false
  )
  |> Stream.flat_map(fn
    {:ok, {:ok, results}} -> results
    _ -> []
  end)
  |> Stream.take(limit)
  |> Enum.each(fn result ->
    callback.(result)
  end)

  :ok
end

defp get_search_shards do
  # Return list of index shards/partitions
  ["default"]
end

defp search_shard(shard, query, opts) do
  with {:ok, adapter} <- get_adapter(:vector_store),
       {:ok, embedder} <- get_adapter(:embedder),
       {:ok, embedding} <- embedder.embed(query) do
    adapter.search(shard, embedding, opts)
  end
end
```

### Task 3: Agent Framework

Create `lib/portfolio_manager/agent.ex`:

```elixir
defmodule PortfolioManager.Agent do
  @moduledoc """
  Tool-using agent for complex code analysis tasks.

  The agent can iteratively use tools to gather information
  and solve problems that require multiple steps.

  ## Example

      PortfolioManager.Agent.run("Find all usages of this function and suggest improvements",
        tools: [:search_code, :read_file, :get_graph_context]
      )
  """

  use GenServer

  require Logger

  alias PortfolioManager.Agent.{Tool, Session}

  @max_iterations 10
  @default_tools [:search_code, :read_file, :list_files, :get_graph_context]

  defstruct [:session_id, :tools, :memory, :iteration]

  # Client API

  @doc """
  Run an agent task.
  """
  @spec run(String.t(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def run(task, opts \\ []) do
    tools = Keyword.get(opts, :tools, @default_tools)
    max_iter = Keyword.get(opts, :max_iterations, @max_iterations)

    session = Session.new()
    loaded_tools = load_tools(tools)

    agent = %__MODULE__{
      session_id: session.id,
      tools: loaded_tools,
      memory: [],
      iteration: 0
    }

    execute_loop(agent, task, max_iter)
  end

  @doc """
  List available tools.
  """
  @spec available_tools() :: [atom()]
  def available_tools do
    Tool.list_all()
    |> Enum.map(& &1.name)
  end

  # Execution Loop

  defp execute_loop(agent, _task, max_iter) when agent.iteration >= max_iter do
    Logger.warning("Agent reached max iterations (#{max_iter})")
    synthesize_answer(agent)
  end

  defp execute_loop(agent, task, max_iter) do
    prompt = build_agent_prompt(agent, task)

    case PortfolioManager.Router.complete([%{role: :user, content: prompt}]) do
      {:ok, %{content: response}} ->
        case parse_response(response) do
          {:tool_call, tool_name, args} ->
            result = execute_tool(agent, tool_name, args)
            new_agent = update_memory(agent, tool_name, args, result)
            execute_loop(new_agent, task, max_iter)

          {:final_answer, answer} ->
            {:ok, answer}

          :continue ->
            execute_loop(%{agent | iteration: agent.iteration + 1}, task, max_iter)
        end

      {:error, reason} ->
        Logger.error("Agent LLM call failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp build_agent_prompt(agent, task) do
    tool_descriptions = format_tools(agent.tools)
    memory = format_memory(agent.memory)

    """
    You are a code analysis agent. Your task is:

    #{task}

    Available tools:
    #{tool_descriptions}

    Conversation history:
    #{memory}

    Instructions:
    - Use tools to gather information needed to complete the task
    - Call one tool at a time using JSON: {"tool": "name", "args": {...}}
    - When ready with final answer: {"answer": "your complete answer"}
    - Be thorough but efficient

    Your response:
    """
  end

  defp format_tools(tools) do
    Enum.map_join(tools, "\n", fn {name, tool} ->
      params = Enum.map_join(tool.parameters, ", ", fn p ->
        "#{p.name}: #{p.type}#{if p.required, do: " (required)", else: ""}"
      end)
      "- #{name}(#{params}): #{tool.description}"
    end)
  end

  defp format_memory([]), do: "No previous actions."

  defp format_memory(memory) do
    Enum.map_join(memory, "\n", fn {tool, args, result} ->
      "Called #{tool}(#{inspect(args)})\nResult: #{String.slice(inspect(result), 0, 500)}"
    end)
  end

  defp parse_response(content) do
    case Regex.run(~r/\{[^{}]+\}/, content) do
      [json] ->
        case Jason.decode(json) do
          {:ok, %{"tool" => name, "args" => args}} ->
            {:tool_call, String.to_atom(name), args}

          {:ok, %{"answer" => answer}} ->
            {:final_answer, answer}

          _ ->
            :continue
        end
      _ ->
        # Check if response contains a final answer
        if String.length(content) > 100 and not String.contains?(content, "{") do
          {:final_answer, content}
        else
          :continue
        end
    end
  end

  defp execute_tool(agent, tool_name, args) do
    case Map.get(agent.tools, tool_name) do
      nil ->
        "Unknown tool: #{tool_name}"

      tool ->
        case tool.execute.(args) do
          {:ok, result} -> result
          {:error, reason} -> "Error: #{inspect(reason)}"
          result -> result
        end
    end
  end

  defp update_memory(agent, tool_name, args, result) do
    %{agent |
      memory: agent.memory ++ [{tool_name, args, result}],
      iteration: agent.iteration + 1
    }
  end

  defp synthesize_answer(agent) do
    if Enum.empty?(agent.memory) do
      {:error, :no_progress}
    else
      summary = format_memory(agent.memory)
      {:ok, "Based on gathered information:\n\n#{summary}"}
    end
  end

  defp load_tools(tool_names) do
    Tool.list_all()
    |> Enum.filter(fn t -> t.name in tool_names end)
    |> Map.new(fn t -> {t.name, t} end)
  end
end
```

### Task 4: Agent Tools

Create `lib/portfolio_manager/agent/tool.ex`:

```elixir
defmodule PortfolioManager.Agent.Tool do
  @moduledoc """
  Tool definitions for the agent framework.
  """

  @type parameter :: %{
    name: atom(),
    type: :string | :integer | :boolean,
    required: boolean(),
    description: String.t()
  }

  @type t :: %{
    name: atom(),
    description: String.t(),
    parameters: [parameter()],
    execute: (map() -> term())
  }

  @doc """
  List all available tools.
  """
  @spec list_all() :: [t()]
  def list_all do
    [
      search_code_tool(),
      read_file_tool(),
      list_files_tool(),
      get_graph_context_tool()
    ]
  end

  defp search_code_tool do
    %{
      name: :search_code,
      description: "Search the codebase for relevant code using semantic similarity",
      parameters: [
        %{name: :query, type: :string, required: true,
          description: "Search query"},
        %{name: :limit, type: :integer, required: false,
          description: "Maximum results (default 5)"}
      ],
      execute: fn args ->
        query = args["query"] || args[:query]
        limit = args["limit"] || args[:limit] || 5
        PortfolioManager.RAG.search(query, limit: limit)
      end
    }
  end

  defp read_file_tool do
    %{
      name: :read_file,
      description: "Read contents of a file from the repository",
      parameters: [
        %{name: :path, type: :string, required: true,
          description: "File path to read"},
        %{name: :start_line, type: :integer, required: false,
          description: "Starting line number"},
        %{name: :end_line, type: :integer, required: false,
          description: "Ending line number"}
      ],
      execute: fn args ->
        path = args["path"] || args[:path]
        start_line = args["start_line"] || args[:start_line]
        end_line = args["end_line"] || args[:end_line]

        case File.read(path) do
          {:ok, content} ->
            content = maybe_slice_lines(content, start_line, end_line)
            {:ok, content}
          error ->
            error
        end
      end
    }
  end

  defp list_files_tool do
    %{
      name: :list_files,
      description: "List files in a directory matching a pattern",
      parameters: [
        %{name: :path, type: :string, required: true,
          description: "Directory path"},
        %{name: :pattern, type: :string, required: false,
          description: "Glob pattern (default: *)"}
      ],
      execute: fn args ->
        path = args["path"] || args[:path]
        pattern = args["pattern"] || args[:pattern] || "*"

        full_pattern = Path.join(path, pattern)
        files = Path.wildcard(full_pattern)
        {:ok, files}
      end
    }
  end

  defp get_graph_context_tool do
    %{
      name: :get_graph_context,
      description: "Get related entities from the knowledge graph",
      parameters: [
        %{name: :entity, type: :string, required: true,
          description: "Entity name to find context for"},
        %{name: :depth, type: :integer, required: false,
          description: "Traversal depth (default 2)"}
      ],
      execute: fn args ->
        entity = args["entity"] || args[:entity]
        depth = args["depth"] || args[:depth] || 2

        # Use default graph
        PortfolioManager.Graph.neighbors("default", entity, depth: depth)
      end
    }
  end

  defp maybe_slice_lines(content, nil, nil), do: content

  defp maybe_slice_lines(content, start_line, end_line) do
    lines = String.split(content, "\n")

    start_idx = (start_line || 1) - 1
    end_idx = (end_line || length(lines)) - 1

    lines
    |> Enum.slice(start_idx..end_idx)
    |> Enum.join("\n")
  end
end
```

Create `lib/portfolio_manager/agent/session.ex`:

```elixir
defmodule PortfolioManager.Agent.Session do
  @moduledoc """
  Agent session management.
  """

  defstruct [:id, :created_at, :messages]

  @type t :: %__MODULE__{
    id: String.t(),
    created_at: DateTime.t(),
    messages: [map()]
  }

  @doc """
  Create a new session.
  """
  @spec new() :: t()
  def new do
    %__MODULE__{
      id: generate_id(),
      created_at: DateTime.utc_now(),
      messages: []
    }
  end

  defp generate_id do
    :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
  end
end
```

### Task 5: Pipeline Orchestration

Create `lib/portfolio_manager/pipeline.ex`:

```elixir
defmodule PortfolioManager.Pipeline do
  @moduledoc """
  DAG-based pipeline orchestration with caching.

  ## Example

      PortfolioManager.Pipeline.run(:code_analysis, %{repo_path: "/path/to/repo"}) do
        step :scan_files, &scan_repo/1
        step :extract_entities, &extract/1, depends_on: [:scan_files]
        step :build_graph, &graph/1, depends_on: [:extract_entities]
        step :generate_summary, &summarize/1, depends_on: [:build_graph]
      end
  """

  require Logger

  defstruct [:name, :steps, :cache_table, :results]

  @type step :: %{
    name: atom(),
    function: fun(),
    depends_on: [atom()],
    timeout: pos_integer(),
    cache: boolean()
  }

  @doc """
  Define and run a pipeline.
  """
  defmacro run(name, context, do: block) do
    quote do
      pipeline = %PortfolioManager.Pipeline{
        name: unquote(name),
        steps: [],
        cache_table: :ets.new(:pipeline_cache, [:set, :public]),
        results: %{}
      }

      var!(pipeline) = pipeline
      unquote(block)

      PortfolioManager.Pipeline.execute(var!(pipeline), unquote(context))
    end
  end

  @doc """
  Add a step to the pipeline.
  """
  defmacro step(name, func, opts \\ []) do
    quote do
      step = %{
        name: unquote(name),
        function: unquote(func),
        depends_on: Keyword.get(unquote(opts), :depends_on, []),
        timeout: Keyword.get(unquote(opts), :timeout, 60_000),
        cache: Keyword.get(unquote(opts), :cache, true)
      }

      var!(pipeline) = update_in(var!(pipeline).steps, &[step | &1])
    end
  end

  @doc """
  Execute a pipeline with dependency resolution.
  """
  @spec execute(%__MODULE__{}, map()) :: {:ok, map()} | {:error, term()}
  def execute(pipeline, context) do
    steps = Enum.reverse(pipeline.steps)
    sorted_steps = topological_sort(steps)

    Enum.reduce_while(sorted_steps, {:ok, %{}}, fn step, {:ok, results} ->
      emit_telemetry(:step_start, %{pipeline: pipeline.name, step: step.name})

      case execute_step(pipeline, step, results, context) do
        {:ok, result} ->
          emit_telemetry(:step_complete, %{pipeline: pipeline.name, step: step.name})
          {:cont, {:ok, Map.put(results, step.name, result)}}

        {:error, reason} = error ->
          emit_telemetry(:step_error, %{pipeline: pipeline.name, step: step.name, error: reason})
          {:halt, error}
      end
    end)
  end

  defp execute_step(pipeline, step, results, context) do
    cache_key = {step.name, :erlang.phash2(context)}

    # Check cache
    if step.cache do
      case :ets.lookup(pipeline.cache_table, cache_key) do
        [{^cache_key, cached}] ->
          Logger.debug("Cache hit for step #{step.name}")
          {:ok, cached}

        [] ->
          do_execute_step(pipeline, step, results, context, cache_key)
      end
    else
      do_execute_step(pipeline, step, results, context, nil)
    end
  end

  defp do_execute_step(pipeline, step, results, context, cache_key) do
    # Build step input from dependencies
    input = build_step_input(step, results, context)

    # Execute with timeout
    task = Task.async(fn -> step.function.(input) end)

    case Task.yield(task, step.timeout) || Task.shutdown(task) do
      {:ok, {:ok, result}} ->
        if cache_key, do: :ets.insert(pipeline.cache_table, {cache_key, result})
        {:ok, result}

      {:ok, {:error, _} = error} ->
        error

      {:ok, result} ->
        if cache_key, do: :ets.insert(pipeline.cache_table, {cache_key, result})
        {:ok, result}

      nil ->
        {:error, {:timeout, step.name}}
    end
  end

  defp build_step_input(step, results, context) do
    deps =
      step.depends_on
      |> Enum.map(fn dep -> {dep, Map.get(results, dep)} end)
      |> Map.new()

    Map.merge(context, %{deps: deps})
  end

  defp topological_sort(steps) do
    # Simple topological sort using Kahn's algorithm
    graph = build_dependency_graph(steps)
    in_degree = calculate_in_degrees(steps, graph)

    do_topo_sort(steps, in_degree, graph, [])
  end

  defp build_dependency_graph(steps) do
    Map.new(steps, fn step -> {step.name, step.depends_on} end)
  end

  defp calculate_in_degrees(steps, graph) do
    initial = Map.new(steps, fn s -> {s.name, 0} end)

    Enum.reduce(graph, initial, fn {_name, deps}, acc ->
      Enum.reduce(deps, acc, fn dep, a ->
        Map.update(a, dep, 0, & &1)
      end)
    end)
    |> then(fn degrees ->
      Enum.reduce(steps, degrees, fn step, acc ->
        Enum.reduce(step.depends_on, acc, fn dep, a ->
          Map.update!(a, step.name, & &1 + 1)
        end)
      end)
    end)
  end

  defp do_topo_sort(steps, in_degree, graph, result) do
    ready =
      in_degree
      |> Enum.filter(fn {_name, degree} -> degree == 0 end)
      |> Enum.map(fn {name, _} -> name end)

    case ready do
      [] when map_size(in_degree) > 0 ->
        raise "Cycle detected in pipeline dependencies"

      [] ->
        Enum.reverse(result)

      _ ->
        ready_steps = Enum.filter(steps, fn s -> s.name in ready end)
        remaining_steps = Enum.reject(steps, fn s -> s.name in ready end)

        new_in_degree =
          in_degree
          |> Map.drop(ready)
          |> then(fn degrees ->
            Enum.reduce(ready, degrees, fn name, acc ->
              dependents =
                Enum.filter(remaining_steps, fn s -> name in s.depends_on end)
                |> Enum.map(& &1.name)

              Enum.reduce(dependents, acc, fn dep, a ->
                Map.update!(a, dep, & &1 - 1)
              end)
            end)
          end)

        do_topo_sort(remaining_steps, new_in_degree, graph, ready_steps ++ result)
    end
  end

  defp emit_telemetry(event, metadata) do
    :telemetry.execute(
      [:portfolio_manager, :pipeline, event],
      %{time: System.monotonic_time()},
      metadata
    )
  end
end
```

### Task 6: Update CLI for Streaming

Update `lib/mix/tasks/portfolio.ask.ex`:

```elixir
# Add streaming option

defp parse_args(args) do
  {opts, args, _} = OptionParser.parse(args,
    strict: [
      strategy: :string,
      top_k: :integer,
      stream: :boolean,
      help: :boolean
    ],
    aliases: [s: :strategy, k: :top_k, h: :help]
  )

  {opts, args}
end

defp run_query(question, opts) do
  strategy = parse_strategy(opts[:strategy])
  top_k = opts[:top_k] || 5

  if opts[:stream] do
    IO.write("\n")

    case PortfolioManager.RAG.stream_query(question, &IO.write/1,
           strategy: strategy, top_k: top_k) do
      :ok ->
        IO.write("\n\n")
      {:error, reason} ->
        IO.puts("\nError: #{inspect(reason)}")
    end
  else
    case PortfolioManager.RAG.query(question, strategy: strategy, top_k: top_k) do
      {:ok, result} ->
        IO.puts("\n#{result.answer}\n")
      {:error, reason} ->
        IO.puts("Error: #{inspect(reason)}")
    end
  end
end
```

### Task 7: Manifest Schema Updates

Update manifest schemas to include router configuration:

```yaml
# config/manifests/development.yml additions

router:
  strategy: fallback
  health_check_interval: 30000
  providers:
    - name: gemini
      module: PortfolioIndex.Adapters.LLM.Gemini
      config:
        model: gemini-2.0-flash-exp
      capabilities:
        - generation
        - code
        - reasoning
      priority: 1

    # Uses claude_agent_sdk wrapper - defaults to SDK's default model
    - name: claude
      module: PortfolioIndex.Adapters.LLM.Anthropic
      config: {}
      capabilities:
        - reasoning
        - analysis
      priority: 2

    # Uses codex_sdk wrapper - defaults to SDK's default model
    - name: openai
      module: PortfolioIndex.Adapters.LLM.OpenAI
      config: {}
      capabilities:
        - generation
        - code
      priority: 3

agent:
  max_iterations: 10
  timeout: 300000
  tools:
    - search_code
    - read_file
    - list_files
    - get_graph_context
```

---

## TDD Process

### Test Files to Create

```
test/router_test.exs
test/agent_test.exs
test/pipeline_test.exs
test/agent/tool_test.exs
test/rag_streaming_test.exs
```

### Example Tests

#### test/router_test.exs

```elixir
defmodule PortfolioManager.RouterTest do
  use ExUnit.Case, async: false

  alias PortfolioManager.Router

  setup do
    # Start router with test providers
    {:ok, _pid} = Router.start_link(
      strategy: :fallback,
      providers: [
        %{name: :test_llm, module: MockLLM, config: %{},
          capabilities: [:generation], priority: 1}
      ]
    )

    on_exit(fn ->
      if Process.whereis(Router), do: GenServer.stop(Router)
    end)

    :ok
  end

  describe "complete/2" do
    test "routes to healthy provider" do
      expect(MockLLM, :complete, fn _msgs, _opts, _config ->
        {:ok, %{content: "test response"}}
      end)

      assert {:ok, %{content: "test response"}} =
        Router.complete([%{role: :user, content: "test"}])
    end

    test "returns error when no healthy providers" do
      Router.register_provider(%{
        name: :unhealthy,
        module: MockLLM,
        config: %{},
        healthy: false
      })

      # Mark all as unhealthy...
      assert {:error, :no_healthy_providers} =
        Router.complete([%{role: :user, content: "test"}])
    end
  end

  describe "strategies" do
    test "fallback uses first healthy provider" do
      Router.set_strategy(:fallback)

      expect(MockLLM, :complete, fn _, _, _ -> {:ok, %{content: "fallback"}} end)

      {:ok, response} = Router.complete([%{role: :user, content: "test"}])
      assert response.content == "fallback"
    end

    test "round_robin distributes requests" do
      Router.set_strategy(:round_robin)

      # Add second provider
      Router.register_provider(%{
        name: :second_llm,
        module: MockLLM2,
        config: %{},
        capabilities: [:generation],
        priority: 2,
        healthy: true
      })

      # Requests should alternate
      # ...
    end

    test "specialist routes by capability" do
      Router.set_strategy(:specialist)

      Router.register_provider(%{
        name: :code_llm,
        module: MockCodeLLM,
        config: %{},
        capabilities: [:code],
        priority: 1,
        healthy: true
      })

      expect(MockCodeLLM, :complete, fn _, _, _ -> {:ok, %{content: "code response"}} end)

      {:ok, response} = Router.complete(
        [%{role: :user, content: "fix this code"}],
        task_type: :code
      )

      assert response.content == "code response"
    end
  end

  describe "health_check/1" do
    test "returns health status" do
      assert Router.health_check(:test_llm) == :healthy
      assert Router.health_check(:unknown) == :unknown
    end
  end
end
```

#### test/agent_test.exs

```elixir
defmodule PortfolioManager.AgentTest do
  use ExUnit.Case, async: true

  alias PortfolioManager.Agent

  describe "run/2" do
    test "executes tool-based task" do
      # Mock the router to return tool calls then final answer
      expect(MockRouter, :complete, fn _msgs ->
        {:ok, %{content: ~s({"tool": "search_code", "args": {"query": "test"}})}}
      end)

      expect(MockRouter, :complete, fn _msgs ->
        {:ok, %{content: ~s({"answer": "Found relevant code"})}}
      end)

      assert {:ok, answer} = Agent.run("Find test code", tools: [:search_code])
      assert String.contains?(answer, "Found")
    end

    test "respects max iterations" do
      # Always return tool calls, never final answer
      expect(MockRouter, :complete, 10, fn _msgs ->
        {:ok, %{content: ~s({"tool": "search_code", "args": {"query": "test"}})}}
      end)

      {:ok, result} = Agent.run("Infinite task", max_iterations: 5)
      # Should synthesize from gathered info
      assert is_binary(result)
    end
  end

  describe "available_tools/0" do
    test "returns list of tool names" do
      tools = Agent.available_tools()

      assert :search_code in tools
      assert :read_file in tools
      assert :list_files in tools
      assert :get_graph_context in tools
    end
  end
end
```

---

## Documentation Updates

### README.md

Add new sections:

```markdown
## Features (v0.3.0)

### Multi-Provider Routing

Route LLM requests across multiple providers with intelligent strategies:

\`\`\`elixir
# Automatic routing
{:ok, response} = PortfolioManager.Router.complete(messages)

# Force specific strategy
{:ok, response} = PortfolioManager.Router.complete(messages, strategy: :specialist)

# Stream responses
PortfolioManager.Router.stream(messages, &IO.write/1)
\`\`\`

### Streaming Responses

Stream RAG query responses for better UX:

\`\`\`elixir
PortfolioManager.RAG.stream_query("How does this work?", fn chunk ->
  IO.write(chunk)
end)

# CLI
mix portfolio.ask "Your question" --stream
\`\`\`

### Agent Framework

Use tool-based agents for complex tasks:

\`\`\`elixir
PortfolioManager.Agent.run("Analyze this codebase and suggest improvements",
  tools: [:search_code, :read_file, :get_graph_context]
)
\`\`\`

### Pipeline Orchestration

Build complex workflows with dependency management:

\`\`\`elixir
import PortfolioManager.Pipeline

run(:analysis, %{repo: "/path/to/repo"}) do
  step :scan, &scan_files/1
  step :analyze, &analyze/1, depends_on: [:scan]
  step :report, &generate_report/1, depends_on: [:analyze]
end
\`\`\`
```

### CHANGELOG.md

```markdown
# Changelog

## [0.3.0] - 2025-12-27

### Added
- `PortfolioManager.Router` - Multi-provider LLM routing
  - Strategies: fallback, round_robin, specialist, cost_optimized
  - Health checking with configurable intervals
  - Streaming support
  - Supports Gemini, Anthropic (via claude_agent_sdk), OpenAI (via codex_sdk)
- `PortfolioManager.RAG.stream_query/3` - Stream RAG responses
- `PortfolioManager.RAG.stream_search/3` - Stream search results
- `PortfolioManager.Agent` - Tool-using agent framework
  - Built-in tools: search_code, read_file, list_files, get_graph_context
  - Configurable max iterations
  - Session management
- `PortfolioManager.Pipeline` - DAG-based workflow orchestration
  - Dependency resolution
  - Step caching
  - Timeout handling
- CLI `--stream` flag for `mix portfolio.ask`
- Manifest configuration for router, agent, and pipelines

### Changed
- Updated dependency on portfolio_core to ~> 0.2.0
- Updated dependency on portfolio_index to ~> 0.2.0

### Dependencies
- Requires portfolio_core ~> 0.2.0
- Requires portfolio_index ~> 0.2.0 (includes claude_agent_sdk and codex_sdk adapters)
```

### New Guides

Create `guides/router.md`, `guides/agent.md`, `guides/pipeline.md`, `guides/streaming.md`

### Examples

Create:
```
examples/router_usage.exs
examples/streaming_query.exs
examples/agent_task.exs
examples/pipeline_workflow.exs
```

#### examples/run_all.sh

```bash
#!/bin/bash
set -e

echo "=== Portfolio Manager Examples ==="
echo ""

echo "1. RAG Query"
mix run examples/rag_query.exs
echo ""

echo "2. Index Repository"
mix run examples/index_repo.exs
echo ""

echo "3. Graph Analysis"
mix run examples/graph_analysis.exs
echo ""

echo "4. Full Workflow"
mix run examples/full_workflow.exs
echo ""

echo "5. Router Usage (v0.3.0)"
mix run examples/router_usage.exs
echo ""

echo "6. Streaming Query (v0.3.0)"
mix run examples/streaming_query.exs
echo ""

echo "7. Agent Task (v0.3.0)"
mix run examples/agent_task.exs
echo ""

echo "8. Pipeline Workflow (v0.3.0)"
mix run examples/pipeline_workflow.exs
echo ""

echo "=== All examples completed successfully ==="
```

---

## Version Bump

### mix.exs

```elixir
def project do
  [
    app: :portfolio_manager,
    version: "0.3.0",
    # ...
  ]
end

defp deps do
  [
    {:portfolio_core, "~> 0.2.0"},
    {:portfolio_index, "~> 0.2.0"},
    # ...
  ]
end
```

---

## Quality Gates

```bash
mix format --check-formatted
mix credo --strict
mix dialyzer
mix test --cover
mix docs
```

### Acceptance Criteria

- [ ] Router module with 4 strategies implemented
- [ ] Router works with SDK-based LLM adapters (Anthropic, OpenAI)
- [ ] Streaming support in RAG and CLI
- [ ] Agent framework with 4 built-in tools
- [ ] Pipeline orchestration with DAG execution
- [ ] All tests passing
- [ ] No compiler warnings
- [ ] No dialyzer errors
- [ ] Credo --strict passes
- [ ] README updated with new features
- [ ] CHANGELOG updated for v0.3.0
- [ ] 4 new guides created
- [ ] All examples work
- [ ] examples/run_all.sh succeeds
- [ ] Version bumped to 0.3.0
- [ ] Dependencies updated to portfolio_core 0.2.0 / portfolio_index 0.2.0

---

## File Checklist

### New Files
- [ ] `lib/portfolio_manager/router.ex`
- [ ] `lib/portfolio_manager/agent.ex`
- [ ] `lib/portfolio_manager/agent/tool.ex`
- [ ] `lib/portfolio_manager/agent/session.ex`
- [ ] `lib/portfolio_manager/pipeline.ex`
- [ ] `test/router_test.exs`
- [ ] `test/agent_test.exs`
- [ ] `test/pipeline_test.exs`
- [ ] `test/agent/tool_test.exs`
- [ ] `guides/router.md`
- [ ] `guides/agent.md`
- [ ] `guides/pipeline.md`
- [ ] `guides/streaming.md`
- [ ] `examples/router_usage.exs`
- [ ] `examples/streaming_query.exs`
- [ ] `examples/agent_task.exs`
- [ ] `examples/pipeline_workflow.exs`

### Modified Files
- [ ] `lib/portfolio_manager/rag.ex` - Add streaming functions
- [ ] `lib/portfolio_manager/application.ex` - Start Router
- [ ] `lib/mix/tasks/portfolio.ask.ex` - Add --stream flag
- [ ] `config/manifests/development.yml` - Router config
- [ ] `config/manifests/production.yml` - Router config
- [ ] `mix.exs` - Version bump + deps
- [ ] `README.md`
- [ ] `CHANGELOG.md`
- [ ] `examples/README.md`
- [ ] `examples/run_all.sh`
