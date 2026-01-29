defmodule PortfolioManager.Router do
  @moduledoc """
  Multi-provider LLM routing with configurable strategies.

  Supports:
  - `:fallback` - Try providers in priority order with failure tracking
  - `:round_robin` - Distribute across healthy providers
  - `:specialist` - Route by task type, capabilities, and keyword detection
  - `:cost_optimized` - Minimize cost while meeting requirements

  Execution uses `nsai_llm` Actions and the configured PortfolioCore LLM adapter.
  Provider modules are optional and only used for health metadata.

  ## New API

  The enhanced API provides more control over routing:

      # Get selected provider without executing
      {:ok, provider} = Router.route(messages, strategy: :specialist, task_type: :code)

      # Route and execute in one call
      {:ok, response} = Router.execute(messages, strategy: :fallback)

      # Execute with automatic retry on failure
      {:ok, response} = Router.execute_with_retry(messages, max_retries: 3)

      # Report results for strategy feedback
      Router.report_result(:gemini, :success, %{latency: 150})
      Router.report_result(:openai, :failure, %{error: :rate_limited})

  ## Configuration

  Configure the LLM adapter under `adapters.llm` and define routing profiles:

      adapters:
        llm:
          adapter: PortfolioIndex.Adapters.LLM.Gemini
          config:
            model: gemini-flash-lite-latest

      router:
        strategy: specialist
        health_check_interval: 30000
        failure_threshold: 3
        providers:
          - name: gemini_fast
            config:
              model: gemini-flash-lite-latest
            capabilities: [generation, code, reasoning]
            priority: 1

  ## Keyword Detection (Specialist Strategy)

  Configure keyword mappings for automatic task type detection:

      keyword_mappings:
        code: ["function", "method", "class", "def", "implement"]
        reasoning: ["explain", "analyze", "why", "compare"]
  """

  @behaviour PortfolioCore.Ports.Router

  use GenServer

  require Logger

  @type strategy :: :fallback | :round_robin | :specialist | :cost_optimized

  @type provider :: %{
          name: atom(),
          module: module() | nil,
          config: map(),
          capabilities: [atom()],
          priority: non_neg_integer(),
          cost_per_token: float() | nil,
          healthy: boolean(),
          last_check: DateTime.t() | nil
        }

  @default_strategy :fallback
  @health_check_interval 30_000
  @failure_threshold 3

  # Client API

  @doc """
  Start the router GenServer.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Select a provider for the given messages and options.

  Returns the selected provider without executing the request.
  """
  @impl true
  @spec route([map()], keyword()) :: {:ok, provider()} | {:error, term()}
  def route(messages, opts \\ []) do
    strategy = Keyword.get(opts, :strategy, get_strategy())
    task_type = Keyword.get(opts, :task_type) || detect_task_type(messages)

    GenServer.call(__MODULE__, {:select_provider, strategy, task_type})
  end

  @doc """
  Route to a provider and execute the request.

  Combines provider selection and request execution in one call.
  """
  @impl true
  @spec execute([map()], keyword()) :: {:ok, map()} | {:error, term()}
  def execute(messages, opts \\ []) do
    with {:ok, provider} <- route(messages, opts) do
      call_provider(provider, :complete, [messages, opts])
    end
  end

  @doc """
  Execute with automatic retry on failure.

  Tries the next available provider if the current one fails.
  """
  @impl true
  @spec execute_with_retry([map()], keyword()) :: {:ok, map()} | {:error, term()}
  def execute_with_retry(messages, opts \\ []) do
    max_retries = Keyword.get(opts, :max_retries, 3)
    retry_delay = Keyword.get(opts, :retry_delay, 100)

    do_execute_with_retry(messages, opts, nil, max_retries, retry_delay)
  end

  defp do_execute_with_retry(_messages, _opts, last_error, 0, _delay) do
    {:error, {:all_providers_failed, last_error}}
  end

  defp do_execute_with_retry(messages, opts, _last_error, retries_left, delay) do
    case execute(messages, opts) do
      {:ok, _} = success ->
        success

      {:error, reason} = error ->
        Logger.warning("Provider failed: #{inspect(reason)}, retrying...")
        Process.sleep(delay)
        do_execute_with_retry(messages, opts, error, retries_left - 1, delay)
    end
  end

  @doc """
  Complete a request using the configured routing strategy.

  Legacy API - prefer `execute/2` for new code.
  """
  @spec complete([map()], keyword()) :: {:ok, map()} | {:error, term()}
  def complete(messages, opts \\ []) do
    execute(messages, opts)
  end

  @doc """
  Stream a response, calling the callback for each chunk.
  """
  @spec stream([map()], (String.t() -> any()), keyword()) :: :ok | {:error, term()}
  def stream(messages, callback, opts \\ []) when is_function(callback, 1) do
    with {:ok, provider} <- route(messages, opts) do
      call_provider(provider, :stream, [messages, callback, opts])
    end
  end

  @doc """
  Report the result of a provider call for strategy feedback.

  Updates failure counts and health status based on results.
  """
  @spec report_result(atom(), :success | :failure, map()) :: :ok
  def report_result(provider_name, result, metadata \\ %{}) do
    GenServer.cast(__MODULE__, {:report_result, provider_name, result, metadata})
  end

  @doc """
  Get the next provider after the current one fails.

  Used for manual fallback handling.
  """
  @spec next_provider(atom(), keyword()) :: {:ok, provider()} | {:error, :no_more}
  def next_provider(current_provider, opts \\ []) do
    GenServer.call(__MODULE__, {:next_provider, current_provider, opts})
  end

  @doc """
  Get a provider by name.
  """
  @spec get_provider(atom()) :: {:ok, provider()} | {:error, :not_found}
  def get_provider(name) do
    GenServer.call(__MODULE__, {:get_provider, name})
  end

  @doc """
  Register a new provider.
  """
  @impl true
  @spec register_provider(map()) :: :ok | {:error, term()}
  def register_provider(provider) do
    GenServer.call(__MODULE__, {:register_provider, provider})
  end

  @doc """
  Remove a provider from the router.
  """
  @impl true
  @spec unregister_provider(atom()) :: :ok
  def unregister_provider(name) do
    GenServer.call(__MODULE__, {:unregister_provider, name})
  end

  @doc """
  Check health status of a specific provider.
  """
  @impl true
  @spec health_check(atom()) :: :healthy | :unhealthy | :unknown
  def health_check(name) do
    GenServer.call(__MODULE__, {:health_check, name})
  end

  @doc """
  List all registered providers.
  """
  @impl true
  @spec list_providers() :: [provider()]
  def list_providers do
    GenServer.call(__MODULE__, :list_providers)
  end

  @doc """
  Get current routing strategy.
  """
  @impl true
  @spec get_strategy() :: strategy()
  def get_strategy do
    GenServer.call(__MODULE__, :get_strategy)
  end

  @doc """
  Set routing strategy.
  """
  @impl true
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
    failure_threshold = Keyword.get(opts, :failure_threshold, @failure_threshold)
    keyword_mappings = Keyword.get(opts, :keyword_mappings, default_keyword_mappings())

    initialized_providers = initialize_providers(providers)
    warn_on_mismatched_providers(initialized_providers)

    state = %{
      strategy: strategy,
      providers: initialized_providers,
      round_robin_index: 0,
      health_check_interval: health_interval,
      failure_threshold: failure_threshold,
      failure_counts: %{},
      keyword_mappings: keyword_mappings
    }

    _ref =
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
  def handle_call({:unregister_provider, name}, _from, state) do
    new_providers = Enum.reject(state.providers, &(&1.name == name))
    {:reply, :ok, %{state | providers: new_providers}}
  end

  @impl true
  def handle_call(:list_providers, _from, state) do
    {:reply, state.providers, state}
  end

  @impl true
  def handle_call({:get_provider, name}, _from, state) do
    case Enum.find(state.providers, &(&1.name == name)) do
      nil -> {:reply, {:error, :not_found}, state}
      provider -> {:reply, {:ok, provider}, state}
    end
  end

  @impl true
  def handle_call({:health_check, name}, _from, state) do
    status =
      case Enum.find(state.providers, &(&1.name == name)) do
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
  def handle_call(:get_keyword_mappings, _from, state) do
    {:reply, state.keyword_mappings, state}
  end

  @impl true
  def handle_call({:select_provider, strategy, task_type}, _from, state) do
    {result, new_state} = do_select_provider(strategy, task_type, state)
    {:reply, result, new_state}
  end

  @impl true
  def handle_call({:next_provider, current, _opts}, _from, state) do
    healthy_providers =
      state.providers
      |> Enum.filter(& &1.healthy)
      |> Enum.sort_by(& &1.priority)

    current_idx = Enum.find_index(healthy_providers, &(&1.name == current))

    result =
      case current_idx do
        nil ->
          {:error, :no_more}

        idx ->
          case Enum.at(healthy_providers, idx + 1) do
            nil -> {:error, :no_more}
            provider -> {:ok, provider}
          end
      end

    {:reply, result, state}
  end

  @impl true
  def handle_cast({:report_result, provider_name, result, _metadata}, state) do
    new_state = update_state_for_result(state, provider_name, result)
    {:noreply, new_state}
  end

  defp update_state_for_result(state, provider_name, :success) do
    %{state | failure_counts: Map.put(state.failure_counts, provider_name, 0)}
  end

  defp update_state_for_result(state, provider_name, :failure) do
    count = Map.get(state.failure_counts, provider_name, 0) + 1
    new_counts = Map.put(state.failure_counts, provider_name, count)
    new_providers = maybe_mark_unhealthy(state, provider_name, count)
    %{state | failure_counts: new_counts, providers: new_providers}
  end

  defp maybe_mark_unhealthy(state, provider_name, count) when count >= state.failure_threshold do
    Enum.map(state.providers, fn p ->
      if p.name == provider_name, do: %{p | healthy: false}, else: p
    end)
  end

  defp maybe_mark_unhealthy(state, _provider_name, _count), do: state.providers

  @impl true
  def handle_info(:health_check, state) do
    new_providers = Enum.map(state.providers, &check_provider_health/1)

    _ref =
      if state.health_check_interval > 0 do
        Process.send_after(self(), :health_check, state.health_check_interval)
      end

    {:noreply, %{state | providers: new_providers}}
  end

  # Private Functions

  defp initialize_providers(providers) do
    providers
    |> Enum.map(fn p ->
      p
      |> Map.update(:config, %{}, fn
        nil -> %{}
        config -> config
      end)
      |> Map.merge(%{healthy: Map.get(p, :healthy, true), last_check: nil})
    end)
    |> Enum.sort_by(& &1.priority)
  end

  defp do_select_provider(:fallback, _task_type, state) do
    healthy =
      state.providers
      |> Enum.filter(fn p ->
        p.healthy and Map.get(state.failure_counts, p.name, 0) < state.failure_threshold
      end)

    case healthy do
      [] -> {{:error, :no_healthy_providers}, state}
      [provider | _] -> {{:ok, provider}, state}
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
      |> Enum.filter(fn p ->
        p.healthy and (task_type == nil or task_type in (p[:capabilities] || []))
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
      |> Enum.filter(fn p ->
        p.healthy and (task_type == nil or task_type in (p[:capabilities] || []))
      end)
      |> Enum.sort_by(&(&1[:cost_per_token] || 0))

    case matching do
      [] -> {{:error, :no_matching_providers}, state}
      [provider | _] -> {{:ok, provider}, state}
    end
  end

  defp detect_task_type(messages) do
    content =
      messages
      |> Enum.map_join(" ", &(Map.get(&1, :content) || Map.get(&1, "content") || ""))
      |> String.downcase()

    # Check against keyword mappings
    GenServer.call(__MODULE__, :get_keyword_mappings)
    |> Enum.find_value(fn {task_type, keywords} ->
      if Enum.any?(keywords, &String.contains?(content, &1)) do
        task_type
      end
    end)
  end

  defp default_keyword_mappings do
    %{
      code: ["function", "method", "class", "def ", "implement", "code", "bug", "fix"],
      reasoning: ["explain", "analyze", "why", "compare", "understand", "reason"],
      generation: ["write", "create", "generate", "draft", "compose"]
    }
  end

  defp call_provider(provider, :complete, [messages, opts]) do
    llm_opts = build_llm_opts(provider, opts)

    case PortfolioManager.LLM.complete(messages, llm_opts) do
      {:ok, _} = success ->
        report_result(provider.name, :success, %{})
        success

      {:error, _} = error ->
        report_result(provider.name, :failure, %{})
        error
    end
  rescue
    e ->
      report_result(provider.name, :failure, %{error: e})
      Logger.error("Provider #{provider.name} failed: #{inspect(e)}")
      {:error, {:provider_error, provider.name, e}}
  end

  defp call_provider(provider, :stream, [messages, callback, opts]) do
    llm_opts = build_llm_opts(provider, opts)

    case PortfolioManager.LLM.stream(messages, llm_opts) do
      {:ok, stream} ->
        Enum.each(stream, callback)
        :ok

      {:error, _} = error ->
        error
    end
  rescue
    e ->
      Logger.error("Provider #{provider.name} failed: #{inspect(e)}")
      {:error, {:provider_error, provider.name, e}}
  end

  defp check_provider_health(provider) do
    healthy = check_health(effective_module(provider), provider.config[:model])
    %{provider | healthy: healthy, last_check: DateTime.utc_now()}
  rescue
    _ -> %{provider | healthy: false, last_check: DateTime.utc_now()}
  end

  defp check_health(module, model) do
    cond do
      is_nil(module) ->
        false

      function_exported?(module, :model_info, 1) ->
        case module.model_info(model) do
          {:ok, _} -> true
          _ -> false
        end

      true ->
        true
    end
  end

  defp build_llm_opts(provider, opts) do
    provider_config = provider.config
    provider_opts = Enum.into(provider_config, [])
    Keyword.merge(provider_opts, opts)
  end

  defp effective_module(%{module: module}) when is_atom(module), do: module
  defp effective_module(_provider), do: configured_llm_module()

  defp configured_llm_module do
    case PortfolioCore.adapter(:llm) do
      {module, _config} -> module
      _ -> nil
    end
  end

  defp warn_on_mismatched_providers(providers) do
    configured = configured_llm_module()

    if configured do
      providers
      |> Enum.reject(&provider_matches_module?(&1, configured))
      |> Enum.each(&log_module_mismatch(&1, configured))
    end
  end

  defp provider_matches_module?(%{module: nil}, _configured), do: true
  defp provider_matches_module?(%{module: module}, configured), do: module == configured

  defp log_module_mismatch(provider, configured) do
    Logger.warning(
      "Router provider #{provider.name} uses #{inspect(provider.module)}, " <>
        "but configured LLM adapter is #{inspect(configured)}. " <>
        "Requests use the configured adapter."
    )
  end
end
