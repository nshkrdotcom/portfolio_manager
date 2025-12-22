defmodule Mix.Tasks.Portfolio.List do
  @moduledoc """
  List tracked repositories in the portfolio.

  ## Usage

      mix portfolio.list [filter-expr] [options]

  ## Options

    * `--status`, `-s` - Filter by status (active, stale, archived, etc.)
    * `--type`, `-t` - Filter by type (library, application, port, etc.)
    * `--language`, `-l` - Filter by language (elixir, python, etc.)
    * `--tag` - Filter by tag (comma-separated or repeatable)
    * `--sort` - Sort by field (name, id, last_commit, commit_count_30d)
    * `--limit`, `-n` - Limit results
    * `--format` - Output format (table, compact, json)
    * `--json` - Output as JSON (same as --format=json)
    * `--help` - Show help message

  ## Examples

      mix portfolio.list
      mix portfolio.list --status=active
      mix portfolio.list --type=library --language=elixir
      mix portfolio.list --tag=core --sort=last_commit
      mix portfolio.list "status=stale AND type=port"
      mix portfolio.list --json

  """
  @shortdoc "List tracked repositories"

  use Mix.Task

  alias PortfolioManager.CLI.Exit

  @impl Mix.Task
  def run(args) do
    {opts, filter_args, _} =
      OptionParser.parse(args,
        strict: [
          status: :string,
          type: :string,
          language: :string,
          tag: :string,
          sort: :string,
          limit: :integer,
          format: :string,
          json: :boolean,
          help: :boolean,
          portfolio_dir: :string
        ],
        aliases: [s: :status, t: :type, l: :language, n: :limit, d: :portfolio_dir]
      )

    if opts[:help] do
      show_help()
    else
      portfolio_path = opts[:portfolio_dir] || default_portfolio_path()
      filter_expr = filter_args |> Enum.join(" ") |> String.trim()
      filter_expr = if filter_expr == "", do: nil, else: filter_expr
      format = normalize_format(opts)

      case PortfolioManager.init(portfolio_path) do
        {:ok, portfolio} ->
          entries =
            portfolio
            |> PortfolioManager.list_repos()
            |> build_entries(portfolio)
            |> apply_option_filters(opts)
            |> apply_filter_expression(filter_expr)
            |> sort_entries(opts[:sort] || "name")
            |> apply_limit(opts[:limit])

          case format do
            "json" -> output_json(entries)
            "compact" -> output_compact(entries)
            _ -> output_table(entries)
          end

        {:error, :not_initialized} ->
          Mix.shell().error("""
          Portfolio not found at #{portfolio_path}
          Run `mix portfolio.init` first.
          """)

          Exit.halt(:config)
      end
    end
  end

  defp normalize_format(opts) do
    cond do
      opts[:json] -> "json"
      is_binary(opts[:format]) -> opts[:format]
      true -> "table"
    end
  end

  defp build_entries(repos, portfolio) do
    Enum.map(repos, fn repo ->
      computed =
        case PortfolioManager.get_context(portfolio, repo.id) do
          {:ok, context} -> context.computed
          _ -> %{}
        end

      %{repo: repo, computed: computed}
    end)
  end

  defp apply_option_filters(entries, opts) do
    entries
    |> maybe_filter(:status, opts[:status])
    |> maybe_filter(:type, opts[:type])
    |> maybe_filter(:language, opts[:language])
    |> maybe_filter_tags(opts[:tag])
  end

  defp apply_filter_expression(entries, nil), do: entries

  defp apply_filter_expression(entries, expr) do
    predicates = parse_filter_expression(expr)

    Enum.filter(entries, fn entry ->
      Enum.all?(predicates, &evaluate_predicate(entry, &1))
    end)
  end

  defp parse_filter_expression(expr) do
    expr
    |> String.split(~r/\s+AND\s+/i)
    |> Enum.map(&String.trim/1)
    |> Enum.map(&parse_predicate/1)
    |> Enum.reject(&is_nil/1)
  end

  defp parse_predicate(predicate) do
    regex = ~r/^([\w\.]+)\s*(==|=|!=|>=|<=|>|<)\s*(.+)$/

    case Regex.run(regex, predicate) do
      [_, field, op, raw_value] ->
        value = parse_filter_value(String.trim(raw_value))
        {String.split(field, "."), op, value}

      _ ->
        nil
    end
  end

  defp parse_filter_value(value) do
    value = String.trim(value)

    value =
      if String.starts_with?(value, "\"") and String.ends_with?(value, "\"") do
        String.trim(value, "\"")
      else
        value
      end

    case Integer.parse(value) do
      {int, ""} -> int
      _ -> value
    end
  end

  defp evaluate_predicate(entry, {path, op, value}) do
    actual = resolve_path(entry, path)
    compare_values(actual, op, value)
  end

  defp resolve_path(%{repo: _repo, computed: computed}, ["computed" | rest]) do
    fetch_nested(computed, rest)
  end

  defp resolve_path(%{repo: repo}, [field]) do
    Map.get(repo, String.to_atom(field))
  end

  defp resolve_path(%{repo: repo}, path) do
    fetch_nested(repo, path)
  end

  defp fetch_nested(map, []), do: map
  defp fetch_nested(nil, _), do: nil

  defp fetch_nested(map, [key | rest]) when is_map(map) do
    value = Map.get(map, key) || Map.get(map, String.to_atom(key))
    fetch_nested(value, rest)
  end

  defp fetch_nested(_, _), do: nil

  defp compare_values(actual, op, value) do
    actual = normalize_compare_value(actual)

    cond do
      op in ["=", "=="] and is_list(actual) ->
        value in actual

      op in ["=", "=="] ->
        actual == value

      op == "!=" and is_list(actual) ->
        value not in actual

      op == "!=" ->
        actual != value

      op in [">", ">=", "<", "<="] ->
        compare_numeric(actual, op, value)

      true ->
        false
    end
  end

  defp compare_numeric(actual, op, value) do
    with {left, right} when is_number(left) and is_number(right) <-
           normalize_numbers(actual, value) do
      case op do
        ">" -> left > right
        ">=" -> left >= right
        "<" -> left < right
        "<=" -> left <= right
      end
    else
      _ -> false
    end
  end

  defp normalize_numbers(actual, value) do
    left =
      case actual do
        v when is_number(v) -> v
        v when is_binary(v) -> String.to_integer(v)
        _ -> nil
      end

    right =
      case value do
        v when is_number(v) -> v
        v when is_binary(v) -> String.to_integer(v)
        _ -> nil
      end

    {left, right}
  rescue
    _ -> {nil, nil}
  end

  defp normalize_compare_value(value) when is_atom(value), do: to_string(value)
  defp normalize_compare_value(value), do: value

  defp maybe_filter(entries, _field, nil), do: entries

  defp maybe_filter(entries, field, value) do
    Enum.filter(entries, fn %{repo: repo} ->
      to_string(Map.get(repo, field)) == value
    end)
  end

  defp maybe_filter_tags(entries, nil), do: entries

  defp maybe_filter_tags(entries, tags) do
    tags =
      tags
      |> String.split(",", trim: true)
      |> Enum.map(&String.trim/1)

    Enum.filter(entries, fn %{repo: repo} ->
      Enum.any?(tags, &(&1 in (repo.tags || [])))
    end)
  end

  defp sort_entries(entries, "id"), do: Enum.sort_by(entries, & &1.repo.id)
  defp sort_entries(entries, "name"), do: Enum.sort_by(entries, & &1.repo.name)

  defp sort_entries(entries, "last_commit") do
    Enum.sort_by(entries, &last_commit_sort_key/1, {:desc, DateTime})
  end

  defp sort_entries(entries, "commit_count_30d") do
    Enum.sort_by(entries, &commit_count_30d/1, :desc)
  end

  defp sort_entries(entries, _), do: entries

  defp apply_limit(entries, nil), do: entries

  defp apply_limit(entries, limit) when is_integer(limit) and limit > 0,
    do: Enum.take(entries, limit)

  defp apply_limit(entries, _), do: entries

  defp output_json(entries) do
    data =
      Enum.map(entries, fn %{repo: repo, computed: computed} ->
        %{
          id: repo.id,
          name: repo.name,
          type: repo.type,
          status: repo.status,
          language: repo.language,
          path: repo.path,
          tags: repo.tags,
          last_commit: last_commit_iso(computed),
          commit_count_30d: commit_count_30d(%{computed: computed})
        }
      end)

    Mix.shell().info(Jason.encode!(data, pretty: true))
  end

  defp output_compact(entries) do
    if Enum.empty?(entries) do
      Mix.shell().info("No repositories found.")
    else
      Enum.each(entries, fn %{repo: repo} ->
        Mix.shell().info("#{repo.id} (#{repo.type}, #{repo.status})")
      end)

      Mix.shell().info("")
      Mix.shell().info("Total: #{length(entries)} repos")
    end
  end

  defp output_table(entries) do
    if Enum.empty?(entries) do
      Mix.shell().info("No repositories found.")
    else
      Mix.shell().info(
        String.pad_trailing("ID", 25) <>
          String.pad_trailing("TYPE", 14) <>
          String.pad_trailing("STATUS", 12) <>
          String.pad_trailing("LANGUAGE", 12) <>
          String.pad_trailing("LAST COMMIT", 14)
      )

      Mix.shell().info(String.duplicate("─", 77))

      Enum.each(entries, fn entry ->
        repo = entry.repo

        Mix.shell().info(
          String.pad_trailing(to_string(repo.id), 25) <>
            String.pad_trailing(to_string(repo.type), 14) <>
            String.pad_trailing(to_string(repo.status), 12) <>
            String.pad_trailing(to_string(repo.language), 12) <>
            String.pad_trailing(format_last_commit(entry), 14)
        )
      end)

      Mix.shell().info("")
      Mix.shell().info("Total: #{length(entries)} repos")
    end
  end

  defp last_commit_datetime(%{computed: computed}) do
    case Map.get(computed, "last_commit") do
      %{"date" => date_str} -> parse_datetime(date_str)
      %{date: date_str} -> parse_datetime(date_str)
      _ -> nil
    end
  end

  defp parse_datetime(nil), do: nil

  defp parse_datetime(%DateTime{} = dt), do: dt

  defp parse_datetime(date_str) when is_binary(date_str) do
    case DateTime.from_iso8601(date_str) do
      {:ok, dt, _} -> dt
      _ -> nil
    end
  end

  defp last_commit_iso(computed) do
    case Map.get(computed, "last_commit") do
      %{"date" => date_str} -> date_str
      %{date: date_str} -> date_str
      _ -> nil
    end
  end

  defp commit_count_30d(%{computed: computed}) do
    value = Map.get(computed, "commit_count_30d") || Map.get(computed, :commit_count_30d)
    if is_integer(value), do: value, else: 0
  end

  defp last_commit_sort_key(entry) do
    last_commit_datetime(entry) || DateTime.from_unix!(0)
  end

  defp format_last_commit(entry) do
    case last_commit_datetime(entry) do
      nil ->
        "N/A"

      %DateTime{} = dt ->
        days = DateTime.diff(DateTime.utc_now(), dt, :day)

        cond do
          days <= 0 -> "today"
          days == 1 -> "1 day ago"
          true -> "#{days} days ago"
        end
    end
  end

  defp show_help do
    Mix.shell().info("""
    Usage: mix portfolio.list [filter-expr] [options]

    List tracked repositories in the portfolio.

    Options:
      --status, -s     Filter by status (active, stale, archived)
      --type, -t       Filter by type (library, application, port)
      --language, -l   Filter by language (elixir, python, javascript)
      --tag            Filter by tag (comma-separated)
      --sort           Sort by field (name, id, last_commit, commit_count_30d)
      --limit, -n      Limit results
      --format         Output format (table, compact, json)
      --json           Output as JSON
      --help           Show this help message

    Examples:
      mix portfolio.list
      mix portfolio.list --status=active --type=library
      mix portfolio.list --tag=core --sort=last_commit
      mix portfolio.list "status=stale AND type=port"
      mix portfolio.list --json
    """)
  end

  defp default_portfolio_path do
    System.get_env("PORTFOLIO_DIR") || Path.join(System.user_home!(), "portfolio")
  end
end
