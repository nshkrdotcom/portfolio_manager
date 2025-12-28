defmodule PortfolioManager.RAG do
  @moduledoc """
  RAG interface for portfolio queries.
  Delegates to portfolio_index strategies via portfolio_core registry.
  """

  alias PortfolioCore.Manifest.Engine
  alias PortfolioCore.Registry
  alias PortfolioIndex.Pipelines.Ingestion

  @doc """
  Query the portfolio using RAG.

  ## Options
    - `:strategy` - RAG strategy to use (default from manifest)
    - `:k` - Number of results to retrieve (default: 10)
    - `:index_id` - Vector index to search (default: "default")
    - `:graph_id` - Graph to use for context (default: "default")
  """
  @spec query(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def query(question, opts \\ []) do
    strategy_name = Keyword.get(opts, :strategy, default_strategy())
    strategy = get_strategy(strategy_name)

    context = build_context(opts)

    case strategy.retrieve(question, context, opts) do
      {:ok, result} ->
        emit_telemetry(:query, result)
        {:ok, result}

      {:error, _} = err ->
        err
    end
  end

  @doc """
  Ask a question and get a generated answer.
  """
  @spec ask(String.t(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def ask(question, opts \\ []) do
    case query(question, opts) do
      {:ok, %{answer: answer}} when is_binary(answer) ->
        {:ok, answer}

      {:ok, %{items: items}} ->
        generate_answer(question, items, opts)

      {:error, _} = err ->
        err
    end
  end

  @doc """
  Search for relevant documents without generating an answer.
  """
  @spec search(String.t(), keyword()) :: {:ok, [map()]} | {:error, term()}
  def search(query_text, opts \\ []) do
    case query(query_text, Keyword.put(opts, :strategy, :hybrid)) do
      {:ok, %{items: items}} -> {:ok, items}
      {:error, _} = err -> err
    end
  end

  @doc """
  Index a repository for RAG queries.
  """
  @spec index_repo(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def index_repo(repo_path, opts \\ []) do
    index_id = Keyword.get(opts, :index_id, "default")
    {vector_store, vector_opts} = get_adapter(:vector_store)
    {embedder, _embedder_opts} = get_adapter(:embedder)

    config = build_index_config(embedder, vector_opts)

    with :ok <- ensure_index(vector_store, index_id, config, opts) do
      files = scan_repo_files(repo_path, opts)

      Enum.each(files, fn file ->
        _ = Ingestion.enqueue(file, index_id: index_id)
      end)

      {:ok, %{files_queued: length(files), index_id: index_id}}
    end
  end

  # Private functions

  defp default_strategy do
    manifest = safe_manifest()
    get_in(manifest, [:rag, :default_strategy]) || :hybrid
  end

  defp get_strategy(name) when is_binary(name), do: name |> String.to_atom() |> get_strategy()
  defp get_strategy(:hybrid), do: PortfolioIndex.RAG.Strategies.Hybrid
  defp get_strategy(:self_rag), do: PortfolioIndex.RAG.Strategies.SelfRAG
  defp get_strategy(:graph_rag), do: PortfolioIndex.RAG.Strategies.GraphRAG
  defp get_strategy(:agentic), do: PortfolioIndex.RAG.Strategies.Agentic
  defp get_strategy(name), do: raise("Unknown RAG strategy: #{name}")

  defp get_adapter(port_name) do
    case Registry.get(port_name) do
      {module, config} -> {module, config}
      nil -> raise "Adapter not configured for #{port_name}"
    end
  end

  defp build_context(opts) do
    %{
      index_id: Keyword.get(opts, :index_id, "default"),
      graph_id: Keyword.get(opts, :graph_id, "default"),
      tenant_id: Keyword.get(opts, :tenant_id),
      adapters: registered_adapters()
    }
  end

  defp registered_adapters do
    [:vector_store, :embedder, :llm, :graph_store, :chunker]
    |> Enum.reduce(%{}, fn port, acc ->
      case Registry.get(port) do
        nil -> acc
        adapter -> Map.put(acc, port, adapter)
      end
    end)
  end

  defp generate_answer(question, items, opts) do
    {llm, llm_opts} = get_adapter(:llm)
    llm_opts = Keyword.merge(llm_opts, Keyword.get(opts, :llm_opts, []))

    context = Enum.map_join(items, "\n\n---\n\n", & &1.content)

    messages = [
      %{
        role: :system,
        content: "Answer the question based on the provided context. Be concise and accurate."
      },
      %{role: :user, content: "Context:\n#{context}\n\nQuestion: #{question}"}
    ]

    case llm.complete(messages, llm_opts) do
      {:ok, %{content: answer}} -> {:ok, answer}
      {:error, _} = err -> err
    end
  end

  defp build_index_config(embedder, vector_opts) do
    model = embedder_model()
    dimensions = embedder_dimensions(embedder, model)

    vector_config = Map.new(vector_opts)

    index_type = normalize_index_type(vector_config[:index_type])
    metric = normalize_metric(vector_config[:metric])

    options =
      vector_config
      |> Map.get(:options, %{})
      |> Map.merge(vector_options_from_manifest(vector_config))

    %{
      dimensions: dimensions,
      metric: metric,
      index_type: index_type,
      options: options
    }
  end

  defp normalize_index_type(nil), do: :ivfflat
  defp normalize_index_type(value) when is_atom(value), do: value

  defp normalize_index_type(value) when is_binary(value) do
    case String.downcase(value) do
      "ivfflat" -> :ivfflat
      "hnsw" -> :hnsw
      "flat" -> :flat
      _ -> :ivfflat
    end
  end

  defp normalize_index_type(_), do: :ivfflat

  defp normalize_metric(nil), do: :cosine
  defp normalize_metric(value) when is_atom(value), do: value

  defp normalize_metric(value) when is_binary(value) do
    case String.downcase(value) do
      "cosine" -> :cosine
      "euclidean" -> :euclidean
      "dot_product" -> :dot_product
      "dot-product" -> :dot_product
      "dotproduct" -> :dot_product
      _ -> :cosine
    end
  end

  defp normalize_metric(_), do: :cosine

  defp embedder_dimensions(embedder, model) do
    manifest = safe_manifest()

    case get_in(manifest, [:adapters, :embedder, :config, :dimensions]) do
      dims when is_integer(dims) -> dims
      _ -> embedder.dimensions(model)
    end
  end

  defp ensure_index(vector_store, index_id, config, opts) do
    case vector_store.create_index(index_id, config) do
      :ok ->
        :ok

      {:error, :already_exists} ->
        :ok

      {:error, {:dimension_mismatch, _}} = err ->
        maybe_recreate_index(vector_store, index_id, config, opts, err)

      {:error, _} = err ->
        err
    end
  end

  defp maybe_recreate_index(vector_store, index_id, config, opts, err) do
    if Keyword.get(opts, :recreate_index, false) do
      recreate_index(vector_store, index_id, config)
    else
      err
    end
  end

  defp recreate_index(vector_store, index_id, config) do
    case vector_store.delete_index(index_id) do
      :ok -> vector_store.create_index(index_id, config)
      {:error, :not_found} -> vector_store.create_index(index_id, config)
      {:error, _} = delete_err -> delete_err
    end
  end

  defp vector_options_from_manifest(vector_config) do
    options = %{}

    options =
      case Map.fetch(vector_config, :lists) do
        {:ok, lists} -> Map.put(options, :lists, lists)
        :error -> options
      end

    options
  end

  defp embedder_model do
    manifest = safe_manifest()
    get_in(manifest, [:adapters, :embedder, :config, :model]) || "text-embedding-3-small"
  end

  defp scan_repo_files(repo_path, opts) do
    extensions = Keyword.get(opts, :extensions, [".ex", ".exs", ".md", ".txt"])
    exclude = Keyword.get(opts, :exclude, ["deps/", "_build/", ".git/"])

    repo_path
    |> Path.join("**/*")
    |> Path.wildcard()
    |> Enum.filter(fn path ->
      File.regular?(path) and
        Enum.any?(extensions, &String.ends_with?(path, &1)) and
        not Enum.any?(exclude, &String.contains?(path, &1))
    end)
    |> Enum.map(fn path ->
      %{
        path: path,
        type: detect_file_type(path)
      }
    end)
  end

  defp detect_file_type(path) do
    cond do
      String.ends_with?(path, [".ex", ".exs"]) -> :elixir
      String.ends_with?(path, ".md") -> :markdown
      String.ends_with?(path, [".py"]) -> :python
      String.ends_with?(path, [".js", ".ts"]) -> :javascript
      true -> :plain
    end
  end

  defp emit_telemetry(event, result) do
    :telemetry.execute(
      [:portfolio_manager, :rag, event],
      %{
        timing_ms: result[:timing_ms] || 0,
        items_count: length(result[:items] || [])
      },
      %{strategy: result[:strategy]}
    )
  end

  defp safe_manifest do
    case Process.whereis(Engine) do
      nil -> %{}
      _pid -> Engine.get_manifest() || %{}
    end
  end
end
