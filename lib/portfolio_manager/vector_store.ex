defmodule PortfolioManager.VectorStore do
  @moduledoc """
  Pgvector-backed storage for documentation chunks.
  """

  import Ecto.Query

  alias Ecto.Adapters.SQL
  alias PortfolioManager.Rag, as: PMRag
  alias PortfolioManager.VectorStore.Repo
  alias Rag.VectorStore.Chunk
  alias Rag.VectorStore.Pgvector, as: RagPgvector
  alias Rag.VectorStore.Store

  @default_embedding_dims 768
  @default_ivfflat_lists 100

  @spec ensure_ready() :: {:ok, RagPgvector.t()} | {:error, term()}
  def ensure_ready do
    with :ok <- ensure_repo_started(),
         :ok <- ensure_schema() do
      {:ok, RagPgvector.new(repo: Repo)}
    end
  end

  @spec ensure_repo_started() :: :ok | {:error, term()}
  def ensure_repo_started do
    case Process.whereis(Repo) do
      nil -> do_start_repo()
      _pid -> :ok
    end
  end

  defp do_start_repo do
    with {:ok, db_opts} <- database_config() do
      :ok = ensure_ecto_started()
      config = Application.get_env(:portfolio_manager, Repo, [])
      config = if Keyword.has_key?(db_opts, :url), do: config, else: Keyword.drop(config, [:url])
      config = Keyword.merge(config, db_opts)
      start_repo_link(config)
    end
  end

  defp start_repo_link(config) do
    case Repo.start_link(config) do
      {:ok, _pid} -> :ok
      {:error, {:already_started, _pid}} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @spec ensure_schema() :: :ok | {:error, term()}
  def ensure_schema do
    embedding_dims =
      Application.get_env(:portfolio_manager, :embedding_dimensions, @default_embedding_dims)

    ivfflat_lists =
      Application.get_env(:portfolio_manager, :vector_index_lists, @default_ivfflat_lists)

    with {:ok, _} <- SQL.query(Repo, "CREATE EXTENSION IF NOT EXISTS vector", []),
         {:ok, _} <- SQL.query(Repo, create_table_sql(embedding_dims), []),
         :ok <- maybe_create_vector_index(embedding_dims, ivfflat_lists),
         {:ok, _} <- SQL.query(Repo, create_fulltext_index_sql(), []) do
      :ok
    else
      {:error, reason} -> {:error, reason}
    end
  end

  @spec delete_by_source_prefix(String.t()) :: {:ok, non_neg_integer()} | {:error, term()}
  def delete_by_source_prefix(prefix) when is_binary(prefix) do
    query = from(c in Chunk, where: like(c.source, ^"#{prefix}%"))

    try do
      {count, _} = Repo.delete_all(query)
      {:ok, count}
    rescue
      error -> {:error, Exception.message(error)}
    end
  end

  @spec insert_chunks([Chunk.t()]) :: {:ok, non_neg_integer()} | {:error, term()}
  def insert_chunks(chunks) when is_list(chunks) do
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    inserts =
      Enum.map(chunks, fn
        %Chunk{} = chunk ->
          %{
            content: chunk.content,
            source: chunk.source,
            embedding: normalize_embedding(chunk.embedding),
            metadata: chunk.metadata || %{},
            inserted_at: now,
            updated_at: now
          }

        %{} = doc ->
          %{
            content: Map.get(doc, :content) || Map.get(doc, "content"),
            source: Map.get(doc, :source) || Map.get(doc, "source"),
            embedding: normalize_embedding(Map.get(doc, :embedding) || Map.get(doc, "embedding")),
            metadata: Map.get(doc, :metadata) || Map.get(doc, "metadata") || %{},
            inserted_at: now,
            updated_at: now
          }
      end)

    try do
      {count, _} = Repo.insert_all(Chunk, inserts)
      {:ok, count}
    rescue
      error -> {:error, Exception.message(error)}
    end
  end

  @spec search(String.t(), keyword()) :: {:ok, [map()]} | {:error, term()}
  def search(query, opts \\ []) when is_binary(query) do
    limit = Keyword.get(opts, :limit, 5)
    repo_id = Keyword.get(opts, :repo_id)

    with {:ok, store} <- ensure_ready(),
         :ok <- ensure_req_started(),
         {:ok, embedding} <- PMRag.embed_one(query) do
      case Store.search(store, embedding, limit: limit) do
        {:ok, results} ->
          {:ok, maybe_filter_results(results, repo_id)}

        {:error, _} = error ->
          error
      end
    end
  end

  defp maybe_filter_results(results, nil), do: results

  defp maybe_filter_results(results, repo_id) do
    Enum.filter(results, fn result ->
      metadata = result.metadata || %{}
      Map.get(metadata, "repo_id") == repo_id or Map.get(metadata, :repo_id) == repo_id
    end)
  end

  defp database_config do
    case get_db_url() do
      url when is_binary(url) and url != "" -> config_from_url(url)
      _ -> config_from_env()
    end
  end

  defp get_db_url do
    System.get_env("PORTFOLIO_DB_URL") || System.get_env("DATABASE_URL")
  end

  defp config_from_url(url) do
    case parse_socket_url(url) do
      {:ok, opts} -> {:ok, opts}
      :skip -> {:ok, [url: url]}
    end
  end

  defp config_from_env do
    socket_dir = System.get_env("PORTFOLIO_DB_SOCKET") || System.get_env("PGHOST")
    database = System.get_env("PORTFOLIO_DB_NAME") || System.get_env("PGDATABASE")

    build_socket_config(socket_dir, database)
  end

  defp build_socket_config(socket_dir, database)
       when is_binary(socket_dir) and is_binary(database) do
    {:ok,
     [
       socket_dir: socket_dir,
       database: database,
       username: get_db_username(),
       password: get_db_password()
     ]}
  end

  defp build_socket_config(_, _), do: {:error, :missing_database_url}

  defp get_db_username do
    System.get_env("PORTFOLIO_DB_USER") || System.get_env("PGUSER")
  end

  defp get_db_password do
    System.get_env("PORTFOLIO_DB_PASSWORD") || System.get_env("PGPASSWORD")
  end

  defp parse_socket_url(url) do
    uri = URI.parse(url)
    query = URI.decode_query(uri.query || "")
    socket = Map.get(query, "host")

    if socket && String.starts_with?(socket, "/") do
      {username, password} = parse_userinfo(uri.userinfo)
      database = uri.path |> to_string() |> String.trim_leading("/")

      {:ok,
       [
         socket_dir: socket,
         database: database,
         username: username,
         password: password
       ]}
    else
      :skip
    end
  end

  defp parse_userinfo(nil), do: {nil, nil}

  defp parse_userinfo(userinfo) do
    case String.split(userinfo, ":", parts: 2) do
      [user, pass] -> {user, pass}
      [user] -> {user, nil}
      _ -> {nil, nil}
    end
  end

  defp ensure_ecto_started do
    apps = [:telemetry, :db_connection, :postgrex, :ecto_sql, :pgvector]

    Enum.each(apps, fn app ->
      _ = Application.ensure_all_started(app)
    end)

    :ok
  end

  defp ensure_req_started do
    _ = Application.ensure_all_started(:req)
    :ok
  end

  defp create_table_sql(embedding_dims) do
    """
    CREATE TABLE IF NOT EXISTS rag_chunks (
      id bigserial PRIMARY KEY,
      content text NOT NULL,
      source text,
      embedding vector(#{embedding_dims}),
      metadata jsonb DEFAULT '{}'::jsonb,
      inserted_at timestamp without time zone,
      updated_at timestamp without time zone
    )
    """
  end

  defp create_vector_index_sql(ivfflat_lists) do
    """
    CREATE INDEX IF NOT EXISTS rag_chunks_embedding_idx
    ON rag_chunks
    USING ivfflat (embedding vector_l2_ops)
    WITH (lists = #{ivfflat_lists})
    """
  end

  defp maybe_create_vector_index(embedding_dims, ivfflat_lists) do
    if embedding_dims <= 2000 do
      case SQL.query(Repo, create_vector_index_sql(ivfflat_lists), []) do
        {:ok, _} -> :ok
        {:error, reason} -> {:error, reason}
      end
    else
      :ok
    end
  end

  defp create_fulltext_index_sql do
    """
    CREATE INDEX IF NOT EXISTS rag_chunks_content_search_idx
    ON rag_chunks
    USING gin (to_tsvector('english', content))
    """
  end

  defp normalize_embedding(nil), do: nil
  defp normalize_embedding(%Pgvector{} = vector), do: vector

  defp normalize_embedding(embedding) when is_list(embedding) do
    Pgvector.new(embedding)
  end
end
