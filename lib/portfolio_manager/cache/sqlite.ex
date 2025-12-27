defmodule PortfolioManager.Cache.SQLite do
  @moduledoc """
  SQLite-based cache for portfolio data.

  Provides fast indexed queries for large portfolios. This is an optional
  performance enhancement - the system works without it using YAML storage.

  Requires the optional `exqlite` dependency to be installed.

  ## Usage

      # Build index for a portfolio
      :ok = SQLite.build_index("~/portfolio")

      # Use a long-lived cache process
      {:ok, cache} = SQLite.start_link(portfolio_path: "~/portfolio")
      SQLite.sync(cache, contexts)

      # Fast indexed queries
      SQLite.search(cache, "orchestration")
      SQLite.filter(cache, language: "elixir", status: :active)

  ## Schema

  The cache stores denormalized repo data for fast queries:
    - repos: id, name, path, type, language, status, priority,
      last_commit_date, commit_count_30d, purpose, notes, context_json, updated_at
    - relationships: type, from_repo, to_repo, details_json
    - repos_fts: FTS5 index for id/name/purpose/notes

  """

  use GenServer

  require Logger

  alias PortfolioManager.Domain.{Context, Repo}

  @type t :: GenServer.server()

  # Check if exqlite is available at runtime
  @doc """
  Returns whether SQLite caching is available.

  SQLite caching requires the optional `exqlite` dependency.
  """
  @spec available?() :: boolean()
  def available?, do: Code.ensure_loaded?(Exqlite.Sqlite3)

  # Client API

  @doc """
  Starts the SQLite cache.

  Returns `{:error, :not_available}` if exqlite is not installed.

  ## Options

    * `:portfolio_path` - Path to portfolio directory (required)
    * `:name` - GenServer name (optional)

  """
  @spec start_link(keyword()) :: GenServer.on_start() | {:error, :not_available}
  def start_link(opts) do
    if available?() do
      name = Keyword.get(opts, :name)
      GenServer.start_link(__MODULE__, opts, name: name)
    else
      {:error, :not_available}
    end
  end

  @doc """
  Returns the index database path for a portfolio.
  """
  @spec index_path(String.t() | GenServer.server()) :: String.t()
  def index_path(portfolio_or_path) do
    path =
      case portfolio_or_path do
        binary when is_binary(binary) -> Path.expand(binary)
        _ -> PortfolioManager.Portfolio.get_storage_state(portfolio_or_path).path
      end

    Path.join([path, ".portfolio", "cache", "index.db"])
  end

  @doc """
  Syncs repositories to the cache.
  """
  @spec sync(t(), [map()]) :: :ok | {:error, term()}
  def sync(cache, repos) do
    GenServer.call(cache, {:sync, repos}, :infinity)
  end

  @doc """
  Builds the SQLite index for a portfolio path or server.
  """
  @spec build_index(String.t() | GenServer.server()) :: :ok | {:error, term()}
  def build_index(portfolio_or_path) do
    with {:ok, portfolio, path} <- resolve_portfolio(portfolio_or_path),
         {:ok, cache} <- start_link(portfolio_path: path) do
      contexts =
        portfolio
        |> PortfolioManager.list_repos()
        |> Enum.flat_map(fn repo ->
          case PortfolioManager.get_context(portfolio, repo.id) do
            {:ok, context} -> [context]
            _ -> []
          end
        end)

      relationships = fetch_relationships(portfolio)

      :ok = sync(cache, contexts)
      :ok = sync_relationships(cache, relationships)
      GenServer.stop(cache)
      :ok
    end
  end

  @doc """
  Syncs relationships to the cache.
  """
  @spec sync_relationships(t(), [map()]) :: :ok | {:error, term()}
  def sync_relationships(cache, relationships) do
    GenServer.call(cache, {:sync_relationships, relationships}, :infinity)
  end

  @doc """
  Searches repos by text query.
  """
  @spec search(t(), String.t()) :: {:ok, [map()]} | {:error, term()}
  def search(cache, query) do
    GenServer.call(cache, {:search, query})
  end

  @doc """
  Filters repos by attributes.

  ## Options

    * `:language` - Filter by language
    * `:type` - Filter by type
    * `:status` - Filter by status
    * `:limit` - Maximum results (default: 100)

  """
  @spec filter(t(), keyword()) :: {:ok, [map()]} | {:error, term()}
  def filter(cache, opts) do
    GenServer.call(cache, {:filter, opts})
  end

  @doc """
  Gets a single repo by ID.
  """
  @spec get(t(), String.t()) :: {:ok, map()} | {:error, :not_found}
  def get(cache, repo_id) do
    GenServer.call(cache, {:get, repo_id})
  end

  @doc """
  Gets cache statistics.
  """
  @spec stats(t()) :: {:ok, map()}
  def stats(cache) do
    GenServer.call(cache, :stats)
  end

  @doc """
  Clears the cache.
  """
  @spec clear(t()) :: :ok
  def clear(cache) do
    GenServer.call(cache, :clear)
  end

  # Server callbacks

  @impl true
  def init(opts) do
    portfolio_path = Keyword.fetch!(opts, :portfolio_path)
    db_path = Path.join([portfolio_path, ".portfolio", "cache", "index.db"])

    case open_database(db_path) do
      {:ok, conn} ->
        {:ok, %{conn: conn, db_path: db_path}}

      {:error, reason} ->
        {:stop, reason}
    end
  end

  @impl true
  def handle_call({:sync, repos}, _from, state) do
    result = do_sync_repos(state.conn, repos)
    {:reply, result, state}
  end

  @impl true
  def handle_call({:sync_relationships, relationships}, _from, state) do
    result = do_sync_relationships(state.conn, relationships)
    {:reply, result, state}
  end

  @impl true
  def handle_call({:search, query}, _from, state) do
    result = do_search(state.conn, query)
    {:reply, result, state}
  end

  @impl true
  def handle_call({:filter, opts}, _from, state) do
    result = do_filter(state.conn, opts)
    {:reply, result, state}
  end

  @impl true
  def handle_call({:get, repo_id}, _from, state) do
    result = do_get(state.conn, repo_id)
    {:reply, result, state}
  end

  @impl true
  def handle_call(:stats, _from, state) do
    result = do_stats(state.conn)
    {:reply, result, state}
  end

  @impl true
  def handle_call(:clear, _from, state) do
    result = do_clear(state.conn)
    {:reply, result, state}
  end

  @impl true
  def terminate(_reason, state) do
    if state[:conn] do
      Exqlite.Sqlite3.close(state.conn)
    end

    :ok
  end

  # Private functions

  defp open_database(db_path) do
    # Ensure directory exists
    db_path |> Path.dirname() |> File.mkdir_p()

    case Exqlite.Sqlite3.open(db_path) do
      {:ok, conn} ->
        case init_schema(conn) do
          :ok -> {:ok, conn}
          error -> error
        end

      {:error, reason} ->
        Logger.warning("SQLite cache unavailable: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp init_schema(conn) do
    # Create repos table
    Exqlite.Sqlite3.execute(conn, """
    CREATE TABLE IF NOT EXISTS repos (
      id TEXT PRIMARY KEY,
      name TEXT,
      path TEXT,
      type TEXT,
      language TEXT,
      status TEXT,
      priority TEXT,
      last_commit_date TEXT,
      commit_count_30d INTEGER,
      purpose TEXT,
      notes TEXT,
      context_json TEXT,
      updated_at TEXT
    )
    """)

    # Create relationships table
    Exqlite.Sqlite3.execute(conn, """
    CREATE TABLE IF NOT EXISTS relationships (
      id INTEGER PRIMARY KEY,
      type TEXT,
      from_repo TEXT,
      to_repo TEXT,
      details_json TEXT
    )
    """)

    # Create FTS table
    Exqlite.Sqlite3.execute(conn, """
    CREATE VIRTUAL TABLE IF NOT EXISTS repos_fts USING fts5(
      id, name, purpose, notes, content='repos'
    )
    """)

    # Create indexes
    Exqlite.Sqlite3.execute(
      conn,
      "CREATE INDEX IF NOT EXISTS idx_repos_language ON repos(language)"
    )

    Exqlite.Sqlite3.execute(conn, "CREATE INDEX IF NOT EXISTS idx_repos_type ON repos(type)")
    Exqlite.Sqlite3.execute(conn, "CREATE INDEX IF NOT EXISTS idx_repos_status ON repos(status)")

    Exqlite.Sqlite3.execute(
      conn,
      "CREATE INDEX IF NOT EXISTS idx_rels_from ON relationships(from_repo)"
    )

    Exqlite.Sqlite3.execute(
      conn,
      "CREATE INDEX IF NOT EXISTS idx_rels_to ON relationships(to_repo)"
    )

    :ok
  rescue
    e ->
      Logger.error("Failed to initialize SQLite schema: #{inspect(e)}")
      {:error, :schema_init_failed}
  end

  defp do_sync_repos(conn, items) do
    Exqlite.Sqlite3.execute(conn, "DELETE FROM repos")

    {:ok, stmt} =
      Exqlite.Sqlite3.prepare(
        conn,
        "INSERT OR REPLACE INTO repos (id, name, path, type, language, status, priority, last_commit_date, commit_count_30d, purpose, notes, context_json, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)"
      )

    Enum.each(items, fn item ->
      row = normalize_repo_row(item)

      Exqlite.Sqlite3.bind(stmt, [
        row.id,
        row.name,
        row.path,
        row.type,
        row.language,
        row.status,
        row.priority,
        row.last_commit_date,
        row.commit_count_30d,
        row.purpose,
        row.notes,
        row.context_json,
        row.updated_at
      ])

      Exqlite.Sqlite3.step(conn, stmt)
      Exqlite.Sqlite3.reset(stmt)
    end)

    Exqlite.Sqlite3.release(conn, stmt)
    rebuild_fts(conn)
  rescue
    e ->
      Logger.error("Failed to sync repos to cache: #{inspect(e)}")
      {:error, :sync_failed}
  end

  defp do_sync_relationships(conn, relationships) do
    Exqlite.Sqlite3.execute(conn, "DELETE FROM relationships")

    {:ok, stmt} =
      Exqlite.Sqlite3.prepare(
        conn,
        "INSERT INTO relationships (type, from_repo, to_repo, details_json) VALUES (?, ?, ?, ?)"
      )

    Enum.each(relationships, fn rel ->
      details_json =
        case Map.get(rel, :details) || Map.get(rel, "details") do
          nil -> nil
          details -> Jason.encode!(details)
        end

      Exqlite.Sqlite3.bind(stmt, [to_string(rel.type), rel.from, rel.to, details_json])
      Exqlite.Sqlite3.step(conn, stmt)
      Exqlite.Sqlite3.reset(stmt)
    end)

    Exqlite.Sqlite3.release(conn, stmt)
    :ok
  rescue
    e ->
      Logger.error("Failed to sync relationships to cache: #{inspect(e)}")
      {:error, :sync_failed}
  end

  defp do_search(conn, query) do
    {:ok, stmt} =
      Exqlite.Sqlite3.prepare(
        conn,
        """
        SELECT repos.id, repos.name, repos.path, repos.type, repos.language, repos.status,
               repos.priority, repos.last_commit_date, repos.commit_count_30d, repos.purpose,
               repos.notes, repos.context_json, repos.updated_at
        FROM repos_fts
        JOIN repos ON repos_fts.rowid = repos.rowid
        WHERE repos_fts MATCH ?
        LIMIT 100
        """
      )

    Exqlite.Sqlite3.bind(stmt, [query])

    rows = fetch_all_rows(conn, stmt)
    Exqlite.Sqlite3.release(conn, stmt)

    repos = Enum.map(rows, &row_to_repo/1)
    {:ok, repos}
  rescue
    e ->
      Logger.error("Search failed: #{inspect(e)}")
      {:error, :search_failed}
  end

  defp do_filter(conn, opts) do
    {conditions, params} = build_filter_conditions(opts)
    limit = opts[:limit] || 100

    where_clause =
      if Enum.empty?(conditions) do
        ""
      else
        "WHERE " <> Enum.join(conditions, " AND ")
      end

    sql =
      "SELECT id, name, path, type, language, status, priority, last_commit_date, commit_count_30d, purpose, notes, context_json, updated_at FROM repos #{where_clause} LIMIT #{limit}"

    {:ok, stmt} = Exqlite.Sqlite3.prepare(conn, sql)

    if not Enum.empty?(params) do
      Exqlite.Sqlite3.bind(stmt, params)
    end

    rows = fetch_all_rows(conn, stmt)
    Exqlite.Sqlite3.release(conn, stmt)

    repos = Enum.map(rows, &row_to_repo/1)
    {:ok, repos}
  rescue
    e ->
      Logger.error("Filter failed: #{inspect(e)}")
      {:error, :filter_failed}
  end

  defp build_filter_conditions(opts) do
    Enum.reduce(opts, {[], []}, fn
      {:language, lang}, {conds, params} ->
        {["language = ?" | conds], params ++ [lang]}

      {:type, type}, {conds, params} ->
        {["type = ?" | conds], params ++ [to_string(type)]}

      {:status, status}, {conds, params} ->
        {["status = ?" | conds], params ++ [to_string(status)]}

      {:priority, priority}, {conds, params} ->
        {["priority = ?" | conds], params ++ [to_string(priority)]}

      _, acc ->
        acc
    end)
  end

  defp do_get(conn, repo_id) do
    {:ok, stmt} =
      Exqlite.Sqlite3.prepare(
        conn,
        "SELECT id, name, path, type, language, status, priority, last_commit_date, commit_count_30d, purpose, notes, context_json, updated_at FROM repos WHERE id = ?"
      )

    Exqlite.Sqlite3.bind(stmt, [repo_id])

    result =
      case Exqlite.Sqlite3.step(conn, stmt) do
        {:row, row} -> {:ok, row_to_repo(row)}
        :done -> {:error, :not_found}
      end

    Exqlite.Sqlite3.release(conn, stmt)
    result
  end

  defp do_stats(conn) do
    repo_count = count_table(conn, "repos")
    rel_count = count_table(conn, "relationships")

    {:ok,
     %{
       repos: repo_count,
       relationships: rel_count
     }}
  end

  defp count_table(conn, table) do
    {:ok, stmt} = Exqlite.Sqlite3.prepare(conn, "SELECT COUNT(*) FROM #{table}")

    result =
      case Exqlite.Sqlite3.step(conn, stmt) do
        {:row, [count]} -> count
        _ -> 0
      end

    Exqlite.Sqlite3.release(conn, stmt)
    result
  end

  defp do_clear(conn) do
    Exqlite.Sqlite3.execute(conn, "DELETE FROM repos")
    Exqlite.Sqlite3.execute(conn, "DELETE FROM repos_fts")
    Exqlite.Sqlite3.execute(conn, "DELETE FROM relationships")
    :ok
  end

  defp fetch_all_rows(conn, stmt) do
    fetch_all_rows(conn, stmt, [])
  end

  defp fetch_all_rows(conn, stmt, acc) do
    case Exqlite.Sqlite3.step(conn, stmt) do
      {:row, row} -> fetch_all_rows(conn, stmt, [row | acc])
      :done -> Enum.reverse(acc)
    end
  end

  defp row_to_repo([
         id,
         name,
         path,
         type,
         language,
         status,
         priority,
         last_commit_date,
         commit_count_30d,
         purpose,
         notes,
         context_json,
         updated_at
       ]) do
    %{
      id: id,
      name: name,
      path: path,
      type: String.to_atom(type || "unknown"),
      language: language,
      status: String.to_atom(status || "unknown"),
      priority: priority && String.to_atom(priority),
      last_commit_date: last_commit_date,
      commit_count_30d: commit_count_30d,
      purpose: purpose,
      notes: notes,
      context: decode_context_json(context_json),
      updated_at: updated_at
    }
  end

  defp row_to_repo(_), do: %{}

  defp decode_context_json(nil), do: %{}

  defp decode_context_json(content) do
    case Jason.decode(content) do
      {:ok, map} -> map
      _ -> %{}
    end
  end

  defp normalize_repo_row(%Context{} = context) do
    computed = context.computed || %{}
    context_json = Jason.encode!(Context.to_map(context))

    build_repo_row(context.repo, computed, context.notes || "", context_json)
  end

  defp normalize_repo_row(%{repo: %Repo{} = repo} = item) do
    computed = get_field(item, :computed) || %{}
    notes = get_field(item, :notes) || ""
    context_json = Jason.encode!(%{repo: Repo.to_map(repo), computed: computed})

    build_repo_row(repo, computed, notes, context_json)
  end

  defp normalize_repo_row(%Repo{} = repo) do
    build_repo_row(repo, %{}, "", nil)
  end

  defp normalize_repo_row(map) when is_map(map) do
    %{
      id: get_field(map, :id),
      name: get_field(map, :name),
      path: get_field(map, :path),
      type: get_field(map, :type) || "unknown",
      language: get_field(map, :language),
      status: get_field(map, :status) || "unknown",
      priority: get_field(map, :priority),
      last_commit_date: get_field(map, :last_commit_date),
      commit_count_30d: get_field(map, :commit_count_30d),
      purpose: get_field(map, :purpose) || "",
      notes: get_field(map, :notes) || "",
      context_json: get_field(map, :context_json),
      updated_at: get_field(map, :updated_at) || DateTime.to_iso8601(DateTime.utc_now())
    }
  end

  defp get_field(map, key) do
    Map.get(map, key) || Map.get(map, to_string(key))
  end

  defp build_repo_row(%Repo{} = repo, computed, notes, context_json) do
    %{
      id: repo.id,
      name: repo.name || repo.id,
      path: repo.path,
      type: to_string(repo.type || "unknown"),
      language: repo.language && to_string(repo.language),
      status: to_string(repo.status || "unknown"),
      priority: repo.priority && to_string(repo.priority),
      last_commit_date: extract_last_commit_date(computed),
      commit_count_30d: extract_commit_count_30d(computed),
      purpose: repo.purpose || "",
      notes: notes,
      context_json: context_json,
      updated_at: DateTime.to_iso8601(DateTime.utc_now())
    }
  end

  defp extract_last_commit_date(computed) do
    case get_field(computed, :last_commit) do
      %{"date" => date} -> date
      %{date: date} -> date
      _ -> nil
    end
  end

  defp extract_commit_count_30d(computed) do
    get_field(computed, :commit_count_30d)
  end

  defp rebuild_fts(conn) do
    Exqlite.Sqlite3.execute(conn, "INSERT INTO repos_fts(repos_fts) VALUES('rebuild')")
    :ok
  end

  defp resolve_portfolio(portfolio) when is_pid(portfolio) or is_atom(portfolio) do
    state = PortfolioManager.Portfolio.get_storage_state(portfolio)
    {:ok, portfolio, state.path}
  end

  defp resolve_portfolio(path) when is_binary(path) do
    expanded = Path.expand(path)

    case PortfolioManager.init(expanded) do
      {:ok, portfolio} -> {:ok, portfolio, expanded}
      {:error, _} = error -> error
    end
  end

  defp fetch_relationships(portfolio) do
    state = PortfolioManager.Portfolio.get_state(portfolio)
    state.registry.relationships
  end
end
