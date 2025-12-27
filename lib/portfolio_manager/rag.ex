defmodule PortfolioManager.Rag do
  @moduledoc """
  RAG (Retrieval-Augmented Generation) integration for Portfolio Manager.

  Provides semantic search, agentic queries, and multi-turn chat capabilities
  using the RAG library with multiple LLM provider support.
  """

  alias PortfolioManager.Rag.Tools
  alias Rag.Agent.Session, as: RagSession
  alias Rag.Ai.Gemini, as: RagGemini

  @tools [
    Tools.SearchRepos,
    Tools.GetRepoContext,
    Tools.ListRepos,
    Tools.FindRelationships,
    Tools.CompareRepos,
    Tools.GetPortfolioStats
  ]

  @doc """
  Returns the list of available portfolio tools for agents.
  """
  @spec tools() :: [module()]
  def tools, do: @tools

  @doc """
  Creates a new RAG router with configured providers.

  ## Options

    * `:providers` - List of provider atoms (default: auto-detect available)
    * `:strategy` - Routing strategy (default: :specialist)

  ## Examples

      {:ok, router} = PortfolioManager.Rag.create_router()
      {:ok, router} = PortfolioManager.Rag.create_router(providers: [:gemini])

  """
  @spec create_router(keyword()) :: {:ok, Rag.Router.t()} | {:error, term()}
  def create_router(opts \\ []) do
    strategy = Keyword.get(opts, :strategy, default_strategy())
    providers = Keyword.get(opts, :providers, nil)

    router_opts = [strategy: strategy]

    router_opts =
      if providers do
        Keyword.put(router_opts, :providers, providers)
      else
        Keyword.put(router_opts, :auto_detect, true)
      end

    Rag.Router.new(router_opts)
  end

  @doc """
  Creates a new agent with portfolio tools.

  ## Options

    * `:provider` - LLM provider to use (default: :gemini)
    * `:max_iterations` - Max tool iterations (default: 10)
    * `:session` - Existing session to continue

  ## Examples

      agent = PortfolioManager.Rag.create_agent(portfolio)

  """
  @spec create_agent(GenServer.server(), keyword()) :: Rag.Agent.Agent.t()
  def create_agent(portfolio, opts \\ []) do
    provider_atom = Keyword.get(opts, :provider, default_provider())
    provider = instantiate_provider(provider_atom)
    max_iterations = Keyword.get(opts, :max_iterations, agent_max_iterations())
    session = Keyword.get(opts, :session, nil)

    registry = Rag.Agent.Registry.new(tools: @tools)

    agent_opts = [
      provider: provider,
      registry: registry,
      max_iterations: max_iterations,
      system_prompt: system_prompt()
    ]

    agent_opts =
      if session do
        Keyword.put(agent_opts, :session, session)
      else
        agent_opts
      end

    agent = Rag.Agent.Agent.new(agent_opts)

    # Add portfolio to context for tools
    Rag.Agent.Agent.with_context(agent, :portfolio, portfolio)
  end

  @doc """
  Creates a new chat session.

  ## Options

    * `:id` - Custom session ID
    * `:metadata` - Additional metadata

  """
  @spec create_session(keyword()) :: Rag.Agent.Session.t()
  def create_session(opts \\ []) do
    RagSession.new(opts)
  end

  @doc """
  Executes an agentic query using tools.

  Returns a result containing the answer and tools used.

  ## Examples

      {:ok, result} = PortfolioManager.Rag.query(portfolio, "Find all my Elixir ports")

  """
  @spec query(GenServer.server(), String.t(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def query(portfolio, question, opts \\ []) do
    agent = create_agent(portfolio, opts)

    case Rag.Agent.Agent.process_with_tools(agent, question) do
      {:ok, response, updated_agent} ->
        {:ok,
         %{
           answer: response,
           tools_used: extract_tools_used(updated_agent),
           session: updated_agent.session
         }}

      {:error, _} = error ->
        error
    end
  end

  @doc """
  Continues a multi-turn chat session.

  ## Examples

      {:ok, session} = PortfolioManager.Rag.create_session()
      {:ok, response, session} = PortfolioManager.Rag.chat(portfolio, session, "Hi")

  """
  @spec chat(GenServer.server(), Rag.Agent.Session.t(), String.t(), keyword()) ::
          {:ok, String.t(), Rag.Agent.Session.t()} | {:error, term()}
  def chat(portfolio, session, message, opts \\ []) do
    agent = create_agent(portfolio, Keyword.put(opts, :session, session))

    case Rag.Agent.Agent.process_with_tools(agent, message) do
      {:ok, response, updated_agent} ->
        {:ok, response, updated_agent.session}

      {:error, _} = error ->
        error
    end
  end

  @doc """
  Generates embeddings for text using the configured provider.

  ## Examples

      {:ok, embeddings} = PortfolioManager.Rag.embed(["text1", "text2"])

  """
  @spec embed([String.t()], keyword()) :: {:ok, [list()]} | {:error, term()}
  def embed(texts, opts \\ []) when is_list(texts) do
    with {:ok, router} <- create_router(opts) do
      Rag.Router.execute(router, :embeddings, texts, opts)
      |> case do
        {:ok, embeddings, _router} -> {:ok, embeddings}
        {:error, _} = error -> error
      end
    end
  end

  @doc """
  Generates a single embedding for text.
  """
  @spec embed_one(String.t(), keyword()) :: {:ok, list()} | {:error, term()}
  def embed_one(text, opts \\ []) do
    case embed([text], opts) do
      {:ok, [embedding]} -> {:ok, embedding}
      {:error, _} = error -> error
    end
  end

  # Private helpers

  defp system_prompt do
    """
    You are a portfolio assistant that helps users explore and understand their
    software projects. You have access to tools for searching repos, getting
    detailed context, finding relationships, and comparing projects.

    When answering questions:
    1. Use the appropriate tools to gather information
    2. Synthesize the results into clear, helpful answers
    3. Reference specific repos by their ID when relevant
    4. Highlight interesting patterns or relationships you discover

    Be concise but thorough. If you need more information to answer fully,
    use the available tools to find it.
    """
  end

  defp extract_tools_used(agent) do
    agent
    |> Rag.Agent.Agent.get_history()
    |> Enum.filter(fn msg -> msg.role == :tool end)
    |> Enum.map(fn msg -> msg.tool_name end)
    |> Enum.uniq()
  end

  defp default_strategy do
    Application.get_env(:rag, :default_strategy, :specialist)
  end

  defp default_provider do
    get_in(Application.get_env(:rag, :agent, %{}), [:default_provider]) || :gemini
  end

  defp agent_max_iterations do
    get_in(Application.get_env(:rag, :agent, %{}), [:max_iterations]) || 10
  end

  defp instantiate_provider(:gemini), do: RagGemini.new(%{})
  defp instantiate_provider(:claude), do: maybe_instantiate(Rag.Ai.Claude)
  defp instantiate_provider(:codex), do: maybe_instantiate(Rag.Ai.Codex)
  defp instantiate_provider(provider) when is_struct(provider), do: provider
  defp instantiate_provider(_), do: RagGemini.new(%{})

  defp maybe_instantiate(module) do
    if Code.ensure_loaded?(module) do
      module.new(%{})
    else
      RagGemini.new(%{})
    end
  end
end
