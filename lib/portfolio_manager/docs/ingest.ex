defmodule PortfolioManager.Docs.Ingest do
  @moduledoc """
  Ingests documentation files from tracked repositories.

  Generates per-repo doc indexes and updates computed context summaries.
  """

  defmodule Config do
    @moduledoc false
    defstruct [
      :portfolio,
      :portfolio_path,
      :include_patterns,
      :exclude_patterns,
      :max_size,
      :max_excerpt,
      :max_summary,
      :only_languages,
      :chunk_max_chars,
      :chunk_overlap,
      :embed_batch_size,
      :delete_existing?,
      :dry_run?,
      :embed?
    ]
  end

  @default_include_patterns ["docs/**/*.md"]
  @default_exclude_patterns ["**/node_modules/**", "**/.git/**", "**/deps/**", "**/_build/**"]
  @default_max_size 200_000
  @default_max_excerpt 300
  @default_max_summary 2000
  @default_only_languages ["elixir"]
  @default_chunk_max_chars 800
  @default_chunk_overlap 100
  @default_embed_batch_size 50
  @default_delete_existing true

  @spec run(GenServer.server(), keyword()) :: {:ok, map()}
  def run(portfolio, opts \\ []) do
    config = build_config(portfolio, opts)
    repos = fetch_repos(portfolio, config, Keyword.get(opts, :repo_id))
    process_repos(repos, config)
  end

  defp build_config(portfolio, opts) do
    config = Keyword.get(opts, :config, %{})
    docs_config = Map.get(config, "docs") || %{}

    %Config{
      portfolio: portfolio,
      portfolio_path: portfolio_path(portfolio),
      include_patterns: build_include_patterns(docs_config),
      exclude_patterns: build_exclude_patterns(docs_config),
      max_size: get_config(docs_config, "max_size") || @default_max_size,
      max_excerpt: get_config(docs_config, "max_excerpt") || @default_max_excerpt,
      max_summary: get_config(docs_config, "max_summary") || @default_max_summary,
      only_languages: build_only_languages(docs_config),
      chunk_max_chars: build_chunk_max_chars(opts, docs_config),
      chunk_overlap: build_chunk_overlap(opts, docs_config),
      embed_batch_size: build_embed_batch_size(opts, docs_config),
      delete_existing?: build_delete_existing(opts, docs_config),
      dry_run?: Keyword.get(opts, :dry_run) == true,
      embed?: build_embed_flag(opts, docs_config)
    }
  end

  defp build_include_patterns(docs_config) do
    normalize_patterns(get_config(docs_config, "include_patterns"), @default_include_patterns)
  end

  defp build_exclude_patterns(docs_config) do
    normalize_patterns(get_config(docs_config, "exclude_patterns"), @default_exclude_patterns)
  end

  defp build_only_languages(docs_config) do
    normalize_languages(get_config(docs_config, "only_languages"), @default_only_languages)
  end

  defp build_chunk_max_chars(opts, docs_config) do
    Keyword.get(opts, :chunk_max_chars) ||
      get_config(docs_config, "chunk_max_chars") ||
      @default_chunk_max_chars
  end

  defp build_chunk_overlap(opts, docs_config) do
    Keyword.get(opts, :chunk_overlap) ||
      get_config(docs_config, "chunk_overlap") ||
      @default_chunk_overlap
  end

  defp build_embed_batch_size(opts, docs_config) do
    Keyword.get(opts, :embed_batch_size) ||
      get_config(docs_config, "embed_batch_size") ||
      @default_embed_batch_size
  end

  defp build_delete_existing(opts, docs_config) do
    value =
      case Keyword.fetch(opts, :delete_existing) do
        {:ok, v} -> v
        :error -> get_config(docs_config, "delete_existing")
      end

    if is_boolean(value), do: value, else: @default_delete_existing
  end

  defp build_embed_flag(opts, docs_config) do
    Keyword.get(opts, :embed) == true or get_config(docs_config, "embed") == true
  end

  defp fetch_repos(portfolio, config, repo_id) do
    portfolio
    |> PortfolioManager.list_repos()
    |> maybe_filter_repo(repo_id)
    |> Enum.filter(&elixir_repo?(&1, config.only_languages))
  end

  defp process_repos(repos, config) do
    {results, totals} =
      Enum.reduce(repos, {[], %{docs: 0, skipped: 0, repos: 0}}, fn repo, {acc, totals} ->
        {result, updated_totals} = process_single_repo(repo, config, totals)
        {[result | acc], updated_totals}
      end)

    {:ok, %{results: Enum.reverse(results), totals: totals}}
  end

  defp process_single_repo(repo, config, totals) do
    case ingest_repo(repo, config) do
      {:ok, result} ->
        updated_totals = %{
          docs: totals.docs + result.docs_indexed,
          skipped: totals.skipped + result.docs_skipped,
          repos: totals.repos + 1
        }

        {result, updated_totals}

      {:error, reason} ->
        error_result = %{repo_id: repo.id, status: :error, reason: inspect(reason)}
        {error_result, totals}
    end
  end

  defp portfolio_path(portfolio) do
    state = PortfolioManager.Portfolio.get_state(portfolio)
    state.path
  end

  defp ingest_repo(repo, _config) when is_nil(repo.path) or repo.path == "" do
    {:ok,
     %{
       repo_id: repo.id,
       status: :skipped,
       reason: "missing_path",
       docs_indexed: 0,
       docs_skipped: 0
     }}
  end

  defp ingest_repo(repo, config) do
    {doc_entries, skipped} = discover_and_build_entries(repo, config)
    index_data = build_index(repo, config, doc_entries)
    docs_summary = build_summary(doc_entries, config.max_summary)
    result = build_result(repo, config, doc_entries, skipped)

    execute_ingest(repo, config, index_data, doc_entries, docs_summary, result)
  end

  defp discover_and_build_entries(repo, config) do
    docs = discover_docs(repo.path, config.include_patterns, config.exclude_patterns)

    docs
    |> Enum.map(&build_doc_entry(&1, repo.path, config.max_size, config.max_excerpt))
    |> Enum.reduce({[], 0}, fn
      {:ok, entry}, {entries, skipped_count} -> {[entry | entries], skipped_count}
      {:skip, _reason}, {entries, skipped_count} -> {entries, skipped_count + 1}
    end)
    |> then(fn {entries, skipped} -> {Enum.reverse(entries), skipped} end)
  end

  defp build_result(repo, config, doc_entries, skipped) do
    %{
      repo_id: repo.id,
      status: if(config.dry_run?, do: :dry_run, else: :ok),
      docs_indexed: length(doc_entries),
      docs_skipped: skipped,
      index_path: index_path(config.portfolio_path, repo.id)
    }
  end

  defp execute_ingest(_repo, %{dry_run?: true}, _index_data, _doc_entries, _docs_summary, result) do
    {:ok, result}
  end

  defp execute_ingest(repo, config, index_data, doc_entries, docs_summary, result) do
    with :ok <- write_index(index_path(config.portfolio_path, repo.id), index_data),
         :ok <- update_context(config.portfolio, repo.id, doc_entries, docs_summary) do
      maybe_embed_docs(repo, config, doc_entries, result)
    end
  end

  defp maybe_embed_docs(_repo, %{embed?: false}, _doc_entries, result) do
    {:ok, result}
  end

  defp maybe_embed_docs(repo, config, doc_entries, result) do
    embed_config = %{
      chunk_max_chars: config.chunk_max_chars,
      chunk_overlap: config.chunk_overlap,
      embed_batch_size: config.embed_batch_size,
      delete_existing?: config.delete_existing?
    }

    with {:ok, embed_result} <- embed_repo_docs(repo, doc_entries, embed_config) do
      {:ok, Map.merge(result, embed_result)}
    end
  end

  defp build_index(repo, config, doc_entries) do
    %{
      "version" => "1.0",
      "repo_id" => repo.id,
      "generated_at" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "source" => %{
        "path" => repo.path,
        "include_patterns" => config.include_patterns,
        "exclude_patterns" => config.exclude_patterns,
        "max_size" => config.max_size
      },
      "docs" => doc_entries
    }
  end

  defp build_summary(doc_entries, max_summary) do
    doc_entries
    |> Enum.map(fn entry ->
      title = Map.get(entry, "title") || ""
      excerpt = Map.get(entry, "excerpt") || ""

      summary =
        if title == "" do
          excerpt
        else
          "#{title}: #{excerpt}"
        end

      String.trim(summary)
    end)
    |> Enum.reject(&(&1 == ":" or &1 == ""))
    |> Enum.join("\n")
    |> String.slice(0, max_summary)
  end

  defp embed_repo_docs(repo, doc_entries, embed_config) do
    with {:ok, _store} <- PortfolioManager.VectorStore.ensure_ready() do
      deleted = maybe_delete_existing(repo.path, embed_config.delete_existing?)
      chunks = build_chunks(repo, doc_entries, embed_config)
      process_chunks(chunks, embed_config.embed_batch_size, deleted)
    end
  end

  defp maybe_delete_existing(repo_path, true) do
    source_prefix = repo_path <> "/"

    case PortfolioManager.VectorStore.delete_by_source_prefix(source_prefix) do
      {:ok, count} -> count
      {:error, _} -> 0
    end
  end

  defp maybe_delete_existing(_repo_path, false), do: 0

  defp build_chunks(repo, doc_entries, embed_config) do
    Enum.flat_map(doc_entries, fn entry ->
      build_entry_chunks(repo, entry, embed_config)
    end)
  end

  defp build_entry_chunks(repo, entry, embed_config) do
    relative = Map.get(entry, "path") || Map.get(entry, :path)
    full_path = Path.join(repo.path, relative)

    case File.read(full_path) do
      {:ok, content} ->
        chunk_doc_content(
          repo,
          entry,
          full_path,
          content,
          embed_config.chunk_max_chars,
          embed_config.chunk_overlap
        )

      {:error, _} ->
        []
    end
  end

  defp process_chunks([], _batch_size, deleted) do
    {:ok, %{chunks_embedded: 0, chunks_deleted: deleted}}
  end

  defp process_chunks(chunks, batch_size, deleted) do
    embed_and_insert_chunks(chunks, batch_size, deleted)
  end

  defp embed_and_insert_chunks(chunks, embed_batch_size, deleted) do
    with {:ok, embedded_chunks} <- embed_chunks(chunks, embed_batch_size),
         {:ok, inserted} <- PortfolioManager.VectorStore.insert_chunks(embedded_chunks) do
      {:ok, %{chunks_embedded: inserted, chunks_deleted: deleted}}
    end
  end

  defp chunk_doc_content(repo, entry, full_path, content, chunk_max_chars, chunk_overlap) do
    relative = Map.get(entry, "path") || Map.get(entry, :path)
    sha = Map.get(entry, "sha256") || Map.get(entry, :sha256)
    title = Map.get(entry, "title") || Map.get(entry, :title)

    chunk_text_simple(content, chunk_max_chars, chunk_overlap)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.with_index()
    |> Enum.map(fn {chunk, index} ->
      Rag.VectorStore.build_chunk(%{
        content: chunk,
        source: full_path,
        metadata: %{
          repo_id: repo.id,
          path: relative,
          title: title,
          sha256: sha,
          chunk_index: index
        }
      })
    end)
  end

  defp embed_chunks(chunks, batch_size) do
    case ensure_gemini_ready() do
      :ok ->
        chunks
        |> Enum.chunk_every(batch_size)
        |> Enum.reduce_while({:ok, []}, fn batch, {:ok, acc} ->
          embed_batch(batch, acc)
        end)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp embed_batch(batch, acc) do
    texts = Enum.map(batch, & &1.content)

    case PortfolioManager.Rag.embed(texts) do
      {:ok, embeddings} ->
        try do
          embedded = Rag.VectorStore.add_embeddings(batch, embeddings)
          {:cont, {:ok, acc ++ embedded}}
        rescue
          error -> {:halt, {:error, Exception.message(error)}}
        end

      {:error, reason} ->
        {:halt, {:error, reason}}
    end
  end

  defp chunk_text_simple(text, max_chars, overlap) do
    max_chars = max(max_chars, 1)
    overlap = min(overlap, max_chars - 1)
    do_chunk_text_simple(text, max_chars, overlap, [])
  end

  defp do_chunk_text_simple(text, max_chars, overlap, acc) do
    if String.length(text) <= max_chars do
      Enum.reverse([text | acc])
    else
      chunk = String.slice(text, 0, max_chars)
      next_start = max_chars - overlap
      remaining = String.slice(text, next_start, String.length(text) - next_start)
      do_chunk_text_simple(remaining, max_chars, overlap, [chunk | acc])
    end
  end

  defp ensure_gemini_ready do
    if Code.ensure_loaded?(Gemini.Config) do
      try do
        _ = Application.ensure_all_started(:req)
        Gemini.Config.validate!()
        :ok
      rescue
        error -> {:error, Exception.message(error)}
      end
    else
      :ok
    end
  end

  defp update_context(portfolio, repo_id, doc_entries, docs_summary) do
    case PortfolioManager.get_context(portfolio, repo_id) do
      {:ok, context} ->
        existing_computed = context.computed

        docs_info = %{
          "count" => length(doc_entries),
          "summary" => docs_summary,
          "generated_at" => DateTime.utc_now() |> DateTime.to_iso8601(),
          "paths" => Enum.map(doc_entries, & &1["path"])
        }

        updated_computed = Map.merge(existing_computed, %{"docs" => docs_info})
        PortfolioManager.update_context(portfolio, repo_id, %{"computed" => updated_computed})
        :ok

      {:error, _} ->
        :ok
    end
  end

  defp index_path(portfolio_path, repo_id) do
    Path.join([portfolio_path, "repos", repo_id, "docs", "index.yml"])
  end

  defp write_index(path, data) do
    File.mkdir_p!(Path.dirname(path))
    write_yaml(path, data)
  end

  defp discover_docs(repo_path, include_patterns, exclude_patterns) do
    include_paths =
      include_patterns
      |> Enum.flat_map(&Path.wildcard(Path.join(repo_path, &1)))

    exclude_paths =
      exclude_patterns
      |> Enum.flat_map(&Path.wildcard(Path.join(repo_path, &1)))
      |> MapSet.new()

    include_paths
    |> Enum.reject(&MapSet.member?(exclude_paths, &1))
    |> Enum.filter(&File.regular?/1)
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp build_doc_entry(path, repo_path, max_size, max_excerpt) do
    case File.stat(path) do
      {:ok, stat} when stat.size <= max_size ->
        case File.read(path) do
          {:ok, content} ->
            relative = Path.relative_to(path, repo_path)
            title = extract_title(content, relative)
            excerpt = extract_excerpt(content, max_excerpt)

            {:ok,
             %{
               "path" => relative,
               "sha256" => hash_content(content),
               "bytes" => stat.size,
               "modified_at" => format_mtime(stat.mtime),
               "title" => title,
               "excerpt" => excerpt
             }}

          {:error, _} ->
            {:skip, :read_failed}
        end

      {:ok, _} ->
        {:skip, :too_large}

      {:error, _} ->
        {:skip, :stat_failed}
    end
  end

  defp extract_title(content, fallback) do
    case Regex.run(~r/^#\s+(.+)$/m, content) do
      [_, title] -> String.trim(title)
      _ -> Path.basename(fallback, ".md")
    end
  end

  defp extract_excerpt(content, max_excerpt) do
    content
    |> strip_front_matter()
    |> String.split(~r/\n\s*\n/, trim: true)
    |> List.first()
    |> Kernel.||("")
    |> String.trim()
    |> String.slice(0, max_excerpt)
  end

  defp strip_front_matter(content) do
    case String.split(content, "\n") do
      ["---" | rest] ->
        case Enum.split_while(rest, &(&1 != "---")) do
          {_front_matter, [_marker | remaining]} -> Enum.join(remaining, "\n")
          _ -> content
        end

      _ ->
        content
    end
  end

  defp hash_content(content) do
    :crypto.hash(:sha256, content) |> Base.encode16(case: :lower)
  end

  defp format_mtime({date, time}) do
    NaiveDateTime.from_erl!({date, time}) |> NaiveDateTime.to_iso8601()
  end

  defp elixir_repo?(repo, allowed_languages) do
    language = repo.language && String.downcase(to_string(repo.language))
    language in allowed_languages
  end

  defp maybe_filter_repo(repos, nil), do: repos
  defp maybe_filter_repo(repos, repo_id), do: Enum.filter(repos, &(&1.id == repo_id))

  defp normalize_languages(nil, default), do: normalize_languages(default, default)

  defp normalize_languages(languages, _default) do
    languages
    |> normalize_patterns([])
    |> Enum.map(&String.downcase(to_string(&1)))
  end

  defp normalize_patterns(nil, default), do: default
  defp normalize_patterns(value, _default) when is_list(value), do: value
  defp normalize_patterns(value, _default) when is_binary(value), do: [value]
  defp normalize_patterns(_value, default), do: default

  defp get_config(config, key) do
    Map.get(config, key) || Map.get(config, to_string(key))
  end

  defp write_yaml(path, data) do
    yaml = yaml_encode(data)
    File.write(path, yaml)
  end

  defp yaml_encode(data) do
    encode_value(data, 0)
  end

  defp encode_value(nil, _indent), do: "null\n"
  defp encode_value(true, _indent), do: "true\n"
  defp encode_value(false, _indent), do: "false\n"
  defp encode_value(v, _indent) when is_number(v), do: "#{v}\n"

  defp encode_value(v, _indent) when is_binary(v) do
    if String.contains?(v, "\n") do
      "|\n" <> indent_multiline(v, 2)
    else
      safe_string(v) <> "\n"
    end
  end

  defp encode_value(v, _indent) when is_atom(v), do: "#{v}\n"

  defp encode_value(list, indent) when is_list(list) do
    if list == [] do
      "[]\n"
    else
      list
      |> Enum.map_join("\n", fn item ->
        encode_list_item(item, indent)
      end)
      |> Kernel.<>("\n")
    end
  end

  defp encode_value(map, indent) when is_map(map) do
    if map == %{} do
      "{}\n"
    else
      map
      |> Enum.sort_by(fn {k, _} -> k end)
      |> Enum.map_join(fn {k, v} ->
        encode_map_entry(k, v, indent)
      end)
    end
  end

  defp encode_list_item(item, indent) do
    item_str = encode_value(item, indent + 2) |> String.trim_trailing("\n")
    spaces = String.duplicate(" ", indent)

    if is_map(item) do
      encode_map_list_item(item_str, spaces)
    else
      "#{spaces}- #{item_str}"
    end
  end

  defp encode_map_list_item(item_str, spaces) do
    [first | rest] = String.split(item_str, "\n")
    first_line = "#{spaces}- #{first}"
    rest_lines = Enum.map(rest, fn line -> "#{spaces}  #{line}" end)
    Enum.join([first_line | rest_lines], "\n")
  end

  defp encode_map_entry(k, v, indent) do
    key = to_string(k)
    spaces = String.duplicate(" ", indent)

    cond do
      is_map(v) and map_size(v) > 0 ->
        "#{spaces}#{key}:\n#{encode_value(v, indent + 2)}"

      is_list(v) and v != [] ->
        "#{spaces}#{key}:\n#{encode_value(v, indent + 2)}"

      true ->
        "#{spaces}#{key}: #{encode_value(v, indent) |> String.trim_leading()}"
    end
  end

  defp safe_string(s) do
    if needs_quoting?(s) do
      "\"#{String.replace(s, "\"", "\\\"")}\""
    else
      s
    end
  end

  defp needs_quoting?(s) do
    String.starts_with?(s, [" ", "-", ":", "#", "!", "?", "@", "&", "*", "`", "'", "\""]) or
      String.contains?(s, [": ", " #"]) or
      s in ["true", "false", "null", "yes", "no", "on", "off"]
  end

  defp indent_multiline(text, spaces) do
    indent = String.duplicate(" ", spaces)

    text
    |> String.split("\n")
    |> Enum.map_join("\n", fn line -> "#{indent}#{line}" end)
  end
end
