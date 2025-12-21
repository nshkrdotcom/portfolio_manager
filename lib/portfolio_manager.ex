defmodule PortfolioManager do
  @moduledoc """
  AI-native personal project intelligence system.

  Portfolio Manager helps you track, manage, and search across all your
  software repositories with semantic understanding.

  ## Quick Start

      # Initialize with a portfolio repo path
      {:ok, portfolio} = PortfolioManager.init("~/portfolio")

      # Scan directories for repos
      {:ok, discovered} = PortfolioManager.scan(portfolio, ["~/projects"])

      # List all tracked repos
      repos = PortfolioManager.list_repos(portfolio)

      # Search across all repos
      results = PortfolioManager.search(portfolio, "authentication")

  ## Configuration

  Configure the default portfolio path in your config:

      config :portfolio_manager,
        portfolio_path: "~/my-portfolio"

  """

  alias PortfolioManager.{Portfolio, Ports}
  alias PortfolioManager.Domain.{Repo, Context, Relationship}

  @type portfolio :: GenServer.server()

  # Initialization

  @doc """
  Initializes a portfolio from the given path.

  If the portfolio doesn't exist, it will be created.

  ## Examples

      {:ok, portfolio} = PortfolioManager.init("~/portfolio")

  """
  @spec init(String.t()) :: {:ok, portfolio()} | {:error, term()}
  def init(path) do
    expanded = Path.expand(path)
    storage_adapter = Ports.Storage.adapter()

    # Create if doesn't exist
    unless storage_adapter.exists?(expanded) do
      :ok = storage_adapter.create(expanded)
    end

    Portfolio.start_link(path: expanded)
  end

  @doc """
  Initializes a portfolio using the configured default path.

  ## Examples

      {:ok, portfolio} = PortfolioManager.init()

  """
  @spec init() :: {:ok, portfolio()} | {:error, term()}
  def init do
    path = Application.get_env(:portfolio_manager, :portfolio_path, "../portfolio")
    init(path)
  end

  # Discovery

  @doc """
  Scans directories for git repositories and adds them to the portfolio.

  Returns the list of newly discovered repos.

  ## Examples

      {:ok, discovered} = PortfolioManager.scan(portfolio, ["~/projects", "~/work"])

  """
  @spec scan(portfolio(), [String.t()]) :: {:ok, [Repo.t()]} | {:error, term()}
  def scan(portfolio, directories) when is_list(directories) do
    Portfolio.scan(portfolio, directories)
  end

  @doc """
  Adds a single repository to the portfolio.

  ## Examples

      {:ok, repo} = PortfolioManager.add(portfolio, "~/projects/my-app")

  """
  @spec add(portfolio(), String.t()) :: {:ok, Repo.t()} | {:error, term()}
  def add(portfolio, path) do
    Portfolio.add_repo(portfolio, path)
  end

  @doc """
  Removes a repository from the portfolio.

  ## Examples

      :ok = PortfolioManager.remove(portfolio, "my-app")

  """
  @spec remove(portfolio(), String.t()) :: :ok | {:error, term()}
  def remove(portfolio, repo_id) do
    Portfolio.remove_repo(portfolio, repo_id)
  end

  # Querying

  @doc """
  Lists all tracked repositories.

  ## Options

    * `:status` - Filter by status (`:active`, `:stale`, etc.)
    * `:type` - Filter by type (`:library`, `:application`, etc.)
    * `:language` - Filter by language
    * `:tags` - Filter by tags (list)
    * `:sort` - Sort by field (`:name`, `:updated_at`)

  ## Examples

      # All repos
      repos = PortfolioManager.list_repos(portfolio)

      # Active Elixir libraries
      repos = PortfolioManager.list_repos(portfolio,
        status: :active,
        type: :library,
        language: :elixir
      )

  """
  @spec list_repos(portfolio(), keyword()) :: [Repo.t()]
  def list_repos(portfolio, opts \\ []) do
    Portfolio.list_repos(portfolio, opts)
  end

  @doc """
  Gets a repository by ID.

  ## Examples

      {:ok, repo} = PortfolioManager.get_repo(portfolio, "my-app")

  """
  @spec get_repo(portfolio(), String.t()) :: {:ok, Repo.t()} | {:error, :not_found}
  def get_repo(portfolio, repo_id) do
    Portfolio.get_repo(portfolio, repo_id)
  end

  @doc """
  Gets the full context for a repository.

  Context includes the repo metadata plus notes, decisions, and computed data.

  ## Examples

      {:ok, context} = PortfolioManager.get_context(portfolio, "my-app")
      context.notes  # => "# My App Notes..."
      context.decisions  # => [%{title: "...", ...}]

  """
  @spec get_context(portfolio(), String.t()) :: {:ok, Context.t()} | {:error, term()}
  def get_context(portfolio, repo_id) do
    Portfolio.get_context(portfolio, repo_id)
  end

  @doc """
  Searches repositories by query string.

  Searches across repo ID, name, purpose, and tags.

  ## Options

    * `:fields` - Fields to search (default: `[:id, :name, :purpose, :tags]`)

  ## Examples

      results = PortfolioManager.search(portfolio, "authentication")

  """
  @spec search(portfolio(), String.t(), keyword()) :: [Repo.t()]
  def search(portfolio, query, opts \\ []) do
    Portfolio.search(portfolio, query, opts)
  end

  # Relationships

  @doc """
  Gets all relationships for a repository.

  ## Examples

      rels = PortfolioManager.get_relationships(portfolio, "my-port")
      # => [%Relationship{from: "my-port", to: "upstream", type: :port_of}]

  """
  @spec get_relationships(portfolio(), String.t()) :: [Relationship.t()]
  def get_relationships(portfolio, repo_id) do
    Portfolio.get_relationships(portfolio, repo_id)
  end

  @doc """
  Adds a relationship between two repositories.

  ## Relationship Types

    * `:depends_on` - A depends on B
    * `:port_of` - A is a port of B
    * `:fork_of` - A is a fork of B
    * `:evolved_from` - A evolved from B
    * `:related_to` - General relationship

  ## Examples

      {:ok, rel} = PortfolioManager.add_relationship(
        portfolio,
        "instructor_ex",
        "instructor-ai/instructor",
        :port_of
      )

  """
  @spec add_relationship(portfolio(), String.t(), String.t(), atom()) ::
          {:ok, Relationship.t()} | {:error, term()}
  def add_relationship(portfolio, from, to, type) do
    Portfolio.add_relationship(portfolio, from, to, type)
  end

  # Context Management

  @doc """
  Updates a repository's context.

  ## Examples

      {:ok, context} = PortfolioManager.update_context(portfolio, "my-app", %{
        type: :library,
        purpose: "Authentication library"
      })

  """
  @spec update_context(portfolio(), String.t(), map()) :: {:ok, Context.t()} | {:error, term()}
  def update_context(portfolio, repo_id, updates) do
    Portfolio.update_context(portfolio, repo_id, updates)
  end

  @doc """
  Adds a note to a repository's context.

  ## Examples

      {:ok, context} = PortfolioManager.add_note(portfolio, "my-app",
        "Discovered that this integrates with the new auth system"
      )

  """
  @spec add_note(portfolio(), String.t(), String.t()) :: {:ok, Context.t()} | {:error, term()}
  def add_note(portfolio, repo_id, content) do
    with {:ok, context} <- Portfolio.get_context(portfolio, repo_id) do
      updated = Context.add_note(context, content)
      {adapter, storage_state} = Portfolio.get_state(portfolio).storage
      :ok = adapter.save_context(storage_state, updated)
      {:ok, updated}
    end
  end

  @doc """
  Adds a decision record to a repository.

  ## Examples

      {:ok, context} = PortfolioManager.add_decision(portfolio, "my-app",
        "Use JWT for authentication",
        "After evaluating options, JWT was chosen because..."
      )

  """
  @spec add_decision(portfolio(), String.t(), String.t(), String.t()) ::
          {:ok, Context.t()} | {:error, term()}
  def add_decision(portfolio, repo_id, title, content) do
    with {:ok, context} <- Portfolio.get_context(portfolio, repo_id) do
      updated = Context.add_decision(context, title, content)
      {adapter, storage_state} = Portfolio.get_state(portfolio).storage
      :ok = adapter.save_context(storage_state, updated)
      {:ok, updated}
    end
  end

  # Status

  @doc """
  Returns portfolio statistics.

  ## Examples

      stats = PortfolioManager.status(portfolio)
      # => %{
      #   total: 45,
      #   by_status: %{active: 32, stale: 8, ...},
      #   by_type: %{library: 20, application: 10, ...},
      #   ...
      # }

  """
  @spec status(portfolio()) :: map()
  def status(portfolio) do
    Portfolio.stats(portfolio)
  end

  @doc """
  Saves the current portfolio state to storage.

  ## Examples

      :ok = PortfolioManager.sync(portfolio)

  """
  @spec sync(portfolio()) :: :ok | {:error, term()}
  def sync(portfolio) do
    Portfolio.save(portfolio)
  end

  @doc """
  Generates computed views for the portfolio.

  Creates aggregated view files in the `views/` directory:
    * `by-status.yml` - Repos grouped by status
    * `by-type.yml` - Repos grouped by type
    * `by-language.yml` - Repos grouped by language
    * `stale-repos.yml` - Repos with no recent activity
    * `port-status.yml` - Port repositories status

  ## Options

    * `:stale_days` - Days threshold for stale detection (default: 90)

  ## Examples

      :ok = PortfolioManager.generate_views(portfolio)

  """
  @spec generate_views(portfolio(), keyword()) :: :ok | {:error, term()}
  def generate_views(portfolio, opts \\ []) do
    PortfolioManager.Views.generate_all(portfolio, opts)
  end

  # RAG-Powered Features

  @doc """
  Performs semantic search across all repositories.

  Uses vector embeddings to find semantically similar content.

  ## Options

    * `:limit` - Maximum results to return (default: 10)
    * `:min_score` - Minimum similarity score (default: 0.5)

  ## Examples

      results = PortfolioManager.semantic_search(portfolio, "error handling patterns")

  """
  @spec semantic_search(portfolio(), String.t(), keyword()) :: [map()]
  def semantic_search(portfolio, query, opts \\ []) do
    limit = Keyword.get(opts, :limit, 10)

    # Get all repos and their contexts
    repos = list_repos(portfolio)

    # Build searchable content from repos
    repo_contents =
      repos
      |> Enum.map(fn repo ->
        context =
          case get_context(portfolio, repo.id) do
            {:ok, ctx} -> ctx
            _ -> nil
          end

        content = build_searchable_content(repo, context)
        {repo, content}
      end)
      |> Enum.filter(fn {_repo, content} -> content != "" end)

    # Generate embeddings for query and repo contents
    case PortfolioManager.Rag.embed_one(query) do
      {:ok, query_embedding} ->
        texts = Enum.map(repo_contents, fn {_repo, content} -> content end)

        case PortfolioManager.Rag.embed(texts) do
          {:ok, content_embeddings} ->
            # Calculate similarities and rank
            repo_contents
            |> Enum.zip(content_embeddings)
            |> Enum.map(fn {{repo, content}, embedding} ->
              score = cosine_similarity(query_embedding, embedding)

              %{
                repo_id: repo.id,
                name: repo.name,
                type: repo.type,
                language: repo.language,
                score: score,
                snippet: String.slice(content, 0, 200)
              }
            end)
            |> Enum.filter(fn result ->
              result.score >= Keyword.get(opts, :min_score, 0.5)
            end)
            |> Enum.sort_by(& &1.score, :desc)
            |> Enum.take(limit)

          {:error, _} ->
            []
        end

      {:error, _} ->
        []
    end
  end

  @doc """
  Performs an agentic query that uses tools to find answers.

  The agent can search repos, get context, compare projects, and more.

  ## Options

    * `:provider` - LLM provider to use (:gemini, :claude, :codex)
    * `:max_iterations` - Maximum tool iterations

  ## Examples

      {:ok, result} = PortfolioManager.query(portfolio,
        "Compare my instructor_ex port to the upstream Python version"
      )

      IO.puts(result.answer)
      IO.inspect(result.tools_used)

  """
  @spec query(portfolio(), String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def query(portfolio, question, opts \\ []) do
    PortfolioManager.Rag.query(portfolio, question, opts)
  end

  @doc """
  Starts a new interactive chat session.

  Sessions maintain conversation history for multi-turn interactions.

  ## Options

    * `:id` - Custom session ID
    * `:metadata` - Additional session metadata

  ## Examples

      {:ok, session} = PortfolioManager.start_session(portfolio)

  """
  @spec start_session(portfolio(), keyword()) :: {:ok, Rag.Agent.Session.t()}
  def start_session(_portfolio, opts \\ []) do
    session = PortfolioManager.Rag.create_session(opts)
    {:ok, session}
  end

  @doc """
  Sends a message in a chat session.

  The agent uses tools to answer questions while maintaining conversation context.

  ## Examples

      {:ok, session} = PortfolioManager.start_session(portfolio)
      {:ok, response, session} = PortfolioManager.chat(portfolio, session, "Show me all Elixir libraries")
      {:ok, response, session} = PortfolioManager.chat(portfolio, session, "Which ones are ports?")

  """
  @spec chat(portfolio(), Rag.Agent.Session.t(), String.t(), keyword()) ::
          {:ok, String.t(), Rag.Agent.Session.t()} | {:error, term()}
  def chat(portfolio, session, message, opts \\ []) do
    PortfolioManager.Rag.chat(portfolio, session, message, opts)
  end

  # Private helpers for semantic search

  defp build_searchable_content(repo, context) do
    parts = [
      repo.name,
      repo.id,
      to_string(repo.type),
      to_string(repo.language),
      Enum.join(repo.tags || [], " ")
    ]

    parts =
      if context do
        parts ++
          [
            context.notes || "",
            format_decisions(context.decisions),
            format_port_info(context.repo.port)
          ]
      else
        parts
      end

    parts
    |> Enum.filter(&(&1 != nil and &1 != ""))
    |> Enum.join(" ")
  end

  defp format_decisions(nil), do: ""

  defp format_decisions(decisions) do
    decisions
    |> Enum.map(fn d -> "#{d.title}: #{d.content}" end)
    |> Enum.join(" ")
  end

  defp format_port_info(nil), do: ""

  defp format_port_info(port) do
    [
      port[:upstream_url],
      port[:upstream_language],
      port[:coverage]
    ]
    |> Enum.filter(&(&1 != nil))
    |> Enum.join(" ")
  end

  defp cosine_similarity(vec_a, vec_b) when is_list(vec_a) and is_list(vec_b) do
    dot = Enum.zip(vec_a, vec_b) |> Enum.reduce(0.0, fn {a, b}, acc -> acc + a * b end)
    mag_a = :math.sqrt(Enum.reduce(vec_a, 0.0, fn x, acc -> acc + x * x end))
    mag_b = :math.sqrt(Enum.reduce(vec_b, 0.0, fn x, acc -> acc + x * x end))

    if mag_a == 0.0 or mag_b == 0.0 do
      0.0
    else
      dot / (mag_a * mag_b)
    end
  end
end
