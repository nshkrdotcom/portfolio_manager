# Portfolio Manager - Implementation Details

**Note:** This depends on portfolio_core v0.2.0 and portfolio_index v0.2.0.

## Feature Specifications

### 1. Multi-Provider LLM Support

#### Manifest Schema Addition

```yaml
# config/manifests/development.yml
version: "1.0"
environment: development

adapters:
  # Primary LLM configuration
  llm:
    module: PortfolioIndex.Adapters.LLM.Gemini
    config:
      model: gemini-flash-lite-latest

  # NEW: Provider pool for routing
  # Note: Anthropic and OpenAI adapters use SDK wrappers (claude_agent_sdk, codex_sdk)
  # They use default models unless overridden
  llm_providers:
    - name: gemini
      module: PortfolioIndex.Adapters.LLM.Gemini
      config:
        model: gemini-flash-lite-latest
      capabilities: [generation, reasoning, code]

    - name: claude
      module: PortfolioIndex.Adapters.LLM.Anthropic
      config: {}  # Uses claude_agent_sdk defaults
      capabilities: [reasoning, analysis]

    - name: openai
      module: PortfolioIndex.Adapters.LLM.OpenAI
      config: {}  # Uses codex_sdk defaults
      capabilities: [generation, code]

  # NEW: Router configuration
  llm_router:
    strategy: specialist  # fallback, round_robin, specialist
    health_check_interval: 30_000
    timeout: 60_000
    retry_count: 2
```

#### Router Module

```elixir
# lib/portfolio_manager/router.ex
defmodule PortfolioManager.Router do
  @moduledoc """
  Multi-provider LLM routing with strategy selection.
  """

  use GenServer

  @type strategy :: :fallback | :round_robin | :specialist
  @type provider :: %{
    name: atom(),
    module: module(),
    config: map(),
    capabilities: [atom()],
    healthy: boolean()
  }

  # Client API

  def complete(messages, opts \\ []) do
    strategy = Keyword.get(opts, :strategy, default_strategy())
    task_type = Keyword.get(opts, :task_type, :generation)

    provider = select_provider(strategy, task_type)
    attempt_completion(provider, messages, opts)
  end

  def stream(messages, callback, opts \\ []) do
    provider = select_provider(opts)
    provider.module.stream(messages, callback, provider.config)
  end

  # Provider Selection

  defp select_provider(:fallback, _task_type) do
    providers()
    |> Enum.filter(& &1.healthy)
    |> List.first()
  end

  defp select_provider(:round_robin, _task_type) do
    providers()
    |> Enum.filter(& &1.healthy)
    |> Enum.at(next_index())
  end

  defp select_provider(:specialist, task_type) do
    providers()
    |> Enum.filter(& &1.healthy)
    |> Enum.filter(&(task_type in &1.capabilities))
    |> Enum.random()
  end

  # Health Checking

  def handle_info(:health_check, state) do
    providers = Enum.map(state.providers, &check_health/1)
    schedule_health_check()
    {:noreply, %{state | providers: providers}}
  end

  defp check_health(provider) do
    case provider.module.health_check(provider.config) do
      :ok -> %{provider | healthy: true}
      {:error, _} -> %{provider | healthy: false}
    end
  end
end
```

### 2. Streaming Response Support

#### RAG Module Extension

```elixir
# lib/portfolio_manager/rag.ex (additions)

@doc """
Stream a RAG query, calling the callback for each chunk.
"""
@spec stream_query(String.t(), (String.t() -> any()), keyword()) :: :ok | {:error, term()}
def stream_query(question, callback, opts \\ []) do
  strategy = Keyword.get(opts, :strategy, :hybrid)
  top_k = Keyword.get(opts, :top_k, 5)

  # Retrieve context (non-streaming)
  {:ok, context} = retrieve(question, strategy, top_k)

  # Build prompt
  prompt = build_prompt(question, context)

  # Stream generation
  with {:ok, llm} <- get_adapter(:llm) do
    llm.stream(prompt, callback, llm_config())
  end
end

@doc """
Stream search results as they're found.
"""
@spec stream_search(String.t(), (map() -> any()), keyword()) :: :ok
def stream_search(query, callback, opts \\ []) do
  limit = Keyword.get(opts, :limit, 10)

  Task.async_stream(
    search_shards(query),
    fn shard -> search_shard(shard, query) end,
    ordered: false
  )
  |> Stream.flat_map(fn {:ok, results} -> results end)
  |> Stream.take(limit)
  |> Enum.each(callback)
end
```

#### CLI Streaming

```elixir
# lib/mix/tasks/portfolio.ask.ex (modifications)

defp run_query(question, opts) do
  if opts[:stream] do
    stream_with_spinner(question, opts)
  else
    sync_query(question, opts)
  end
end

defp stream_with_spinner(question, opts) do
  IO.write("\n")

  PortfolioManager.RAG.stream_query(question, fn chunk ->
    IO.write(chunk)
  end, opts)

  IO.write("\n\n")
end
```

### 3. Agent Framework

#### Agent Module

```elixir
# lib/portfolio_manager/agent.ex
defmodule PortfolioManager.Agent do
  @moduledoc """
  Tool-using agent for complex code analysis tasks.
  """

  use GenServer

  alias PortfolioManager.Agent.{Session, Tool, Executor}

  @max_iterations 10

  defstruct [:session_id, :tools, :memory, :llm]

  # Public API

  @spec run(String.t(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def run(task, opts \\ []) do
    tools = Keyword.get(opts, :tools, default_tools())
    session = Session.new()

    agent = %__MODULE__{
      session_id: session.id,
      tools: load_tools(tools),
      memory: [],
      llm: get_llm()
    }

    execute_loop(agent, task, 0)
  end

  # Execution Loop

  defp execute_loop(_agent, _task, iteration) when iteration >= @max_iterations do
    {:error, :max_iterations_reached}
  end

  defp execute_loop(agent, task, iteration) do
    # Build prompt with tool descriptions
    prompt = build_agent_prompt(agent, task)

    # Get LLM response
    {:ok, response} = agent.llm.complete(prompt)

    # Parse for tool calls
    case parse_tool_calls(response) do
      [] ->
        # No tool calls, return final answer
        {:ok, extract_answer(response)}

      tool_calls ->
        # Execute tools and continue
        results = execute_tools(agent, tool_calls)
        agent = update_memory(agent, tool_calls, results)
        execute_loop(agent, task, iteration + 1)
    end
  end

  # Tool Execution

  defp execute_tools(agent, tool_calls) do
    Enum.map(tool_calls, fn %{tool: name, args: args} ->
      tool = Map.get(agent.tools, name)
      Executor.run(tool, args)
    end)
  end

  defp default_tools do
    [:search_code, :read_file, :get_graph_context, :list_files]
  end
end
```

#### Tool Behavior

```elixir
# lib/portfolio_manager/agent/tool.ex
defmodule PortfolioManager.Agent.Tool do
  @moduledoc """
  Behavior for agent tools.
  """

  @callback name() :: atom()
  @callback description() :: String.t()
  @callback parameters() :: [parameter()]
  @callback execute(args :: map()) :: {:ok, term()} | {:error, term()}

  @type parameter :: %{
    name: String.t(),
    type: :string | :integer | :boolean | :list,
    required: boolean(),
    description: String.t()
  }
end
```

#### Built-in Tools

```elixir
# lib/portfolio_manager/agent/tools/search_code.ex
defmodule PortfolioManager.Agent.Tools.SearchCode do
  @behaviour PortfolioManager.Agent.Tool

  @impl true
  def name, do: :search_code

  @impl true
  def description do
    "Search the codebase for relevant code snippets using semantic search."
  end

  @impl true
  def parameters do
    [
      %{name: "query", type: :string, required: true,
        description: "The search query"},
      %{name: "limit", type: :integer, required: false,
        description: "Maximum results (default 5)"}
    ]
  end

  @impl true
  def execute(%{"query" => query} = args) do
    limit = Map.get(args, "limit", 5)
    PortfolioManager.RAG.search(query, limit: limit)
  end
end

# lib/portfolio_manager/agent/tools/read_file.ex
defmodule PortfolioManager.Agent.Tools.ReadFile do
  @behaviour PortfolioManager.Agent.Tool

  @impl true
  def name, do: :read_file

  @impl true
  def description do
    "Read the contents of a file from the indexed repository."
  end

  @impl true
  def parameters do
    [
      %{name: "path", type: :string, required: true,
        description: "The file path to read"},
      %{name: "start_line", type: :integer, required: false,
        description: "Starting line number"},
      %{name: "end_line", type: :integer, required: false,
        description: "Ending line number"}
    ]
  end

  @impl true
  def execute(%{"path" => path} = args) do
    start_line = Map.get(args, "start_line")
    end_line = Map.get(args, "end_line")

    with {:ok, content} <- File.read(path) do
      content = maybe_slice_lines(content, start_line, end_line)
      {:ok, content}
    end
  end
end

# lib/portfolio_manager/agent/tools/graph_context.ex
defmodule PortfolioManager.Agent.Tools.GraphContext do
  @behaviour PortfolioManager.Agent.Tool

  @impl true
  def name, do: :get_graph_context

  @impl true
  def description do
    "Get related entities from the knowledge graph."
  end

  @impl true
  def parameters do
    [
      %{name: "entity", type: :string, required: true,
        description: "The entity to find context for"},
      %{name: "depth", type: :integer, required: false,
        description: "Traversal depth (default 2)"}
    ]
  end

  @impl true
  def execute(%{"entity" => entity} = args) do
    depth = Map.get(args, "depth", 2)
    graph_id = get_default_graph()

    PortfolioManager.Graph.neighbors(graph_id, entity, depth: depth)
  end
end
```

### 4. Pipeline Orchestration

#### Pipeline Module

```elixir
# lib/portfolio_manager/pipeline.ex
defmodule PortfolioManager.Pipeline do
  @moduledoc """
  DAG-based pipeline orchestration with caching.
  """

  alias PortfolioManager.Pipeline.{Step, Executor, Cache}

  defstruct [:name, :steps, :cache_table]

  @doc """
  Define and run a pipeline.
  """
  defmacro run(name, context, do: block) do
    quote do
      pipeline = %PortfolioManager.Pipeline{
        name: unquote(name),
        steps: [],
        cache_table: :ets.new(:pipeline_cache, [:set, :public])
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
      step = %Step{
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
  Execute a pipeline with topological ordering.
  """
  def execute(pipeline, context) do
    steps = topological_sort(pipeline.steps)
    results = %{}

    Enum.reduce_while(steps, {:ok, results}, fn step, {:ok, acc} ->
      case execute_step(pipeline, step, acc, context) do
        {:ok, result} -> {:cont, {:ok, Map.put(acc, step.name, result)}}
        {:error, _} = error -> {:halt, error}
      end
    end)
  end

  defp execute_step(pipeline, step, results, context) do
    # Check cache
    cache_key = {step.name, :erlang.phash2(context)}

    case Cache.get(pipeline.cache_table, cache_key) do
      {:ok, cached} when step.cache ->
        {:ok, cached}

      _ ->
        # Build step input
        input = build_step_input(step, results, context)

        # Execute with timeout
        task = Task.async(fn -> step.function.(input) end)

        case Task.yield(task, step.timeout) || Task.shutdown(task) do
          {:ok, result} ->
            if step.cache, do: Cache.put(pipeline.cache_table, cache_key, result)
            {:ok, result}

          nil ->
            {:error, {:timeout, step.name}}
        end
    end
  end
end
```

## Module Structure

```
lib/portfolio_manager/
├── rag.ex                    # Enhanced with streaming
├── graph.ex                  # Existing
├── router.ex                 # NEW: Multi-provider routing
├── agent.ex                  # NEW: Agent framework
├── pipeline.ex               # NEW: Pipeline orchestration
├── cache.ex                  # NEW: Caching layer
│
├── agent/
│   ├── tool.ex               # Tool behavior
│   ├── session.ex            # Session management
│   ├── executor.ex           # Tool execution
│   └── tools/
│       ├── search_code.ex
│       ├── read_file.ex
│       ├── graph_context.ex
│       └── list_files.ex
│
├── pipeline/
│   ├── step.ex               # Step struct
│   ├── executor.ex           # DAG executor
│   └── cache.ex              # Step caching
│
└── domain/
    └── registry.ex           # Existing
```
