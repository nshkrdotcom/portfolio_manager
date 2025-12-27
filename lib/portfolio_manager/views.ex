defmodule PortfolioManager.Views do
  @moduledoc """
  Computed views for portfolio data.

  Generates aggregated views that are auto-updated after sync operations.
  Views are stored in the `views/` directory of the portfolio.
  """

  # Suppress dialyzer warning for defensive error handling
  @dialyzer {:nowarn_function, generate_stale_repos: 3}

  alias PortfolioManager.Adapters.LocalGit

  @doc """
  Generates all computed views for a portfolio.

  ## Options

    * `:stale_days` - Days since last commit to consider stale (default: 90)

  """
  @spec generate_all(GenServer.server(), keyword()) :: :ok | {:error, term()}
  def generate_all(portfolio, opts \\ []) do
    repos = PortfolioManager.list_repos(portfolio)

    with :ok <- generate_by_status(portfolio, repos),
         :ok <- generate_by_type(portfolio, repos),
         :ok <- generate_by_language(portfolio, repos),
         :ok <- generate_stale_repos(portfolio, repos, opts) do
      generate_port_status(portfolio, repos)
    end
  end

  @doc """
  Generates view grouped by status.
  """
  @spec generate_by_status(GenServer.server(), [map()]) :: :ok | {:error, term()}
  def generate_by_status(portfolio, repos) do
    data = %{
      "generated_at" => DateTime.to_iso8601(DateTime.utc_now()),
      "query" => "GROUP BY status",
      "results" =>
        repos
        |> Enum.group_by(& &1.status)
        |> Enum.map(fn {status, status_repos} ->
          %{
            "status" => to_string(status),
            "count" => length(status_repos),
            "repos" => Enum.map(status_repos, & &1.id)
          }
        end)
        |> Enum.sort_by(& &1["count"], :desc),
      "summary" => %{
        "total" => length(repos),
        "status_counts" =>
          repos
          |> Enum.group_by(& &1.status)
          |> Map.new(fn {k, v} -> {to_string(k), length(v)} end)
      }
    }

    write_view(portfolio, "by-status.yml", data)
  end

  @doc """
  Generates view grouped by type.
  """
  @spec generate_by_type(GenServer.server(), [map()]) :: :ok | {:error, term()}
  def generate_by_type(portfolio, repos) do
    data = %{
      "generated_at" => DateTime.to_iso8601(DateTime.utc_now()),
      "query" => "GROUP BY type",
      "results" =>
        repos
        |> Enum.group_by(& &1.type)
        |> Enum.map(fn {type, type_repos} ->
          %{
            "type" => to_string(type),
            "count" => length(type_repos),
            "repos" => Enum.map(type_repos, & &1.id)
          }
        end)
        |> Enum.sort_by(& &1["count"], :desc),
      "summary" => %{
        "total" => length(repos),
        "type_counts" =>
          repos
          |> Enum.group_by(& &1.type)
          |> Map.new(fn {k, v} -> {to_string(k), length(v)} end)
      }
    }

    write_view(portfolio, "by-type.yml", data)
  end

  @doc """
  Generates view grouped by language.
  """
  @spec generate_by_language(GenServer.server(), [map()]) :: :ok | {:error, term()}
  def generate_by_language(portfolio, repos) do
    data = %{
      "generated_at" => DateTime.to_iso8601(DateTime.utc_now()),
      "query" => "GROUP BY language",
      "results" =>
        repos
        |> Enum.group_by(& &1.language)
        |> Enum.map(fn {lang, lang_repos} ->
          %{
            "language" => to_string(lang),
            "count" => length(lang_repos),
            "repos" => Enum.map(lang_repos, & &1.id)
          }
        end)
        |> Enum.sort_by(& &1["count"], :desc),
      "summary" => %{
        "total" => length(repos)
      }
    }

    write_view(portfolio, "by-language.yml", data)
  end

  @doc """
  Generates view of stale repositories.

  A repo is considered stale if it has no commits in the last N days.

  ## Options

    * `:stale_days` - Days threshold (default: 90)

  """
  @spec generate_stale_repos(GenServer.server(), [map()], keyword()) :: :ok | {:error, term()}
  def generate_stale_repos(portfolio, repos, opts \\ []) do
    stale_days = Keyword.get(opts, :stale_days, 90)

    stale_repos =
      repos
      |> Enum.filter(&repo_is_stale?(&1, portfolio, stale_days))
      |> Enum.map(&build_stale_repo_entry(&1, portfolio))
      |> Enum.sort_by(& &1["days_since_commit"], :desc)

    data = %{
      "generated_at" => DateTime.to_iso8601(DateTime.utc_now()),
      "query" => "status == stale OR (status == active AND computed.commit_count_30d == 0)",
      "threshold_days" => stale_days,
      "results" => stale_repos,
      "summary" => %{
        "total" => length(stale_repos),
        "recommendation" => "Review these repos and update status"
      }
    }

    write_view(portfolio, "stale-repos.yml", data)
  end

  defp repo_is_stale?(repo, portfolio, stale_days) do
    computed = load_computed(portfolio, repo)
    commit_count = get_computed_value(computed, "commit_count_30d")
    last_commit_date = get_last_commit_date(repo, computed)
    days_since_commit = days_since(last_commit_date)

    check_stale_conditions(repo, commit_count, days_since_commit, stale_days)
  end

  defp check_stale_conditions(repo, _commit_count, _days_since_commit, _stale_days)
       when repo.status == :stale,
       do: true

  defp check_stale_conditions(repo, commit_count, _days_since_commit, _stale_days)
       when repo.status == :active and commit_count == 0,
       do: true

  defp check_stale_conditions(_repo, nil, days_since_commit, stale_days)
       when is_integer(days_since_commit),
       do: days_since_commit >= stale_days

  defp check_stale_conditions(_repo, _commit_count, _days_since_commit, _stale_days), do: false

  defp build_stale_repo_entry(repo, portfolio) do
    computed = load_computed(portfolio, repo)
    last_commit_date = get_last_commit_date(repo, computed)
    days = days_since(last_commit_date) || 0
    notes = note_snippet(portfolio, repo.id)

    %{
      "id" => repo.id,
      "status" => to_string(repo.status),
      "days_since_commit" => days,
      "last_commit" => format_commit_date(last_commit_date),
      "recommendation" => stale_recommendation(days)
    }
    |> maybe_add_notes(notes)
  end

  defp format_commit_date(nil), do: nil
  defp format_commit_date(date), do: DateTime.to_iso8601(date)

  defp stale_recommendation(days) when days >= 180, do: "Consider archiving"
  defp stale_recommendation(days) when days >= 90, do: "Mark as stale or maintenance"
  defp stale_recommendation(_days), do: "Review activity"

  defp maybe_add_notes(entry, nil), do: entry
  defp maybe_add_notes(entry, notes), do: Map.put(entry, "notes", notes)

  @doc """
  Generates view of port repositories status.
  """
  @spec generate_port_status(GenServer.server(), [map()]) :: :ok | {:error, term()}
  def generate_port_status(portfolio, repos) do
    port_repos =
      repos
      |> Enum.filter(&(&1.type == :port))
      |> Enum.map(&build_port_entry/1)

    data = %{
      "generated_at" => DateTime.to_iso8601(DateTime.utc_now()),
      "query" => "type == port",
      "results" => port_repos,
      "summary" => build_port_summary(port_repos)
    }

    write_view(portfolio, "port-status.yml", data)
  end

  defp build_port_entry(repo) do
    port_info = repo.port || %{}
    commits_behind = extract_commits_behind(port_info)

    %{
      "id" => repo.id,
      "upstream" => extract_upstream(port_info) |> to_string(),
      "upstream_version" => extract_upstream_version(port_info) |> to_string(),
      "synced_version" => extract_synced_version(port_info) |> to_string(),
      "commits_behind" => commits_behind,
      "status" => port_sync_status(commits_behind),
      "affected_modules" => extract_affected_modules(port_info)
    }
  end

  defp extract_upstream(port_info) do
    get_port_field(port_info, [:upstream_url, :upstream], "unknown")
  end

  defp extract_upstream_version(port_info) do
    get_port_field(port_info, [:upstream_version], nil) ||
      get_nested_port_field(port_info, :sync, :last_tag) ||
      "unknown"
  end

  defp extract_synced_version(port_info) do
    get_port_field(port_info, [:synced_version], nil) ||
      get_nested_port_field(port_info, :sync, :last_tag) ||
      "unknown"
  end

  defp extract_commits_behind(port_info) do
    value =
      get_nested_port_field(port_info, :upstream_status, :commits_behind) ||
        get_port_field(port_info, [:commits_behind], nil)

    normalize_integer(value)
  end

  defp extract_affected_modules(port_info) do
    get_nested_port_field(port_info, :upstream_status, :affected_modules) ||
      get_nested_port_field(port_info, :sync, :affected_modules)
  end

  defp get_port_field(port_info, keys, default) do
    Enum.find_value(keys, default, fn key ->
      Map.get(port_info, key) || Map.get(port_info, to_string(key))
    end)
  end

  defp get_nested_port_field(port_info, outer_key, inner_key) do
    get_in(port_info, [outer_key, inner_key]) ||
      get_in(port_info, [to_string(outer_key), to_string(inner_key)])
  end

  defp port_sync_status(commits_behind) when is_integer(commits_behind) and commits_behind > 0,
    do: "needs_sync"

  defp port_sync_status(commits_behind) when is_integer(commits_behind) and commits_behind == 0,
    do: "up_to_date"

  defp port_sync_status(_), do: "unknown"

  defp build_port_summary(port_repos) do
    summary_counts =
      port_repos
      |> Enum.group_by(& &1["status"])
      |> Map.new(fn {k, v} -> {k, length(v)} end)

    total_commits_behind =
      port_repos
      |> Enum.map(& &1["commits_behind"])
      |> Enum.filter(&is_integer/1)
      |> Enum.sum()

    %{
      "total_ports" => length(port_repos),
      "up_to_date" => Map.get(summary_counts, "up_to_date", 0),
      "needs_sync" => Map.get(summary_counts, "needs_sync", 0),
      "total_commits_behind" => total_commits_behind
    }
  end

  # Private helpers

  defp write_view(portfolio, filename, data) do
    state = PortfolioManager.Portfolio.get_storage_state(portfolio)
    views_dir = Path.join(state.path, "views")

    with :ok <- File.mkdir_p(views_dir) do
      content = yaml_encode(data)
      File.write(Path.join(views_dir, filename), content)
    end
  end

  defp yaml_encode(data) do
    "# AUTO-GENERATED - Do not edit manually\n" <> do_yaml_encode(data, 0)
  end

  defp do_yaml_encode(nil, _indent), do: "null\n"
  defp do_yaml_encode(true, _indent), do: "true\n"
  defp do_yaml_encode(false, _indent), do: "false\n"
  defp do_yaml_encode(v, _indent) when is_number(v), do: "#{v}\n"
  defp do_yaml_encode(v, _indent) when is_atom(v), do: "#{v}\n"

  defp do_yaml_encode(v, _indent) when is_binary(v) do
    if String.contains?(v, "\n") do
      "|\n  " <> String.replace(v, "\n", "\n  ") <> "\n"
    else
      safe_string(v) <> "\n"
    end
  end

  defp do_yaml_encode([], _indent), do: "[]\n"

  defp do_yaml_encode(list, indent) when is_list(list) do
    spaces = String.duplicate(" ", indent)

    list
    |> Enum.map_join("\n", &encode_list_item(&1, spaces, indent))
    |> Kernel.<>("\n")
  end

  defp do_yaml_encode(%{} = map, _indent) when map == %{}, do: "{}\n"

  defp do_yaml_encode(map, indent) when is_map(map) do
    spaces = String.duplicate(" ", indent)

    map
    |> Enum.sort_by(fn {k, _} -> k end)
    |> Enum.map_join(&encode_kv_pair(&1, spaces, indent))
  end

  defp encode_list_item(item, spaces, indent) when is_map(item) do
    item_str = do_yaml_encode(item, indent + 2) |> String.trim_trailing("\n")
    [first | rest] = String.split(item_str, "\n")
    first_line = "#{spaces}- #{first}"
    rest_lines = Enum.map(rest, &"#{spaces}  #{&1}")
    Enum.join([first_line | rest_lines], "\n")
  end

  defp encode_list_item(item, spaces, indent) do
    item_str = do_yaml_encode(item, indent + 2) |> String.trim_trailing("\n")
    "#{spaces}- #{item_str}"
  end

  defp encode_kv_pair({k, v}, spaces, indent) do
    key = to_string(k)

    cond do
      is_map(v) and map_size(v) > 0 ->
        "#{spaces}#{key}:\n#{do_yaml_encode(v, indent + 2)}"

      is_list(v) and v != [] ->
        "#{spaces}#{key}:\n#{do_yaml_encode(v, indent + 2)}"

      true ->
        "#{spaces}#{key}: #{do_yaml_encode(v, indent) |> String.trim_leading()}"
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

  defp load_computed(portfolio, repo) do
    case PortfolioManager.get_context(portfolio, repo.id) do
      {:ok, context} -> context.computed
      _ -> %{}
    end
  end

  defp get_computed_value(computed, key) do
    Map.get(computed, key) || Map.get(computed, String.to_atom(key))
  end

  defp get_last_commit_date(repo, computed) do
    case get_computed_value(computed, "last_commit") do
      %{"date" => date} -> parse_datetime(date)
      %{date: date} -> parse_datetime(date)
      date when is_binary(date) -> parse_datetime(date)
      _ -> fallback_last_commit_date(repo)
    end
  end

  defp fallback_last_commit_date(repo) do
    case repo.path && LocalGit.get_last_commit_date(repo.path) do
      {:ok, %DateTime{} = date} -> date
      _ -> nil
    end
  end

  defp parse_datetime(%DateTime{} = date), do: date

  defp parse_datetime(date) when is_binary(date) do
    case DateTime.from_iso8601(date) do
      {:ok, dt, _} -> dt
      {:error, _} -> nil
    end
  end

  defp parse_datetime(_), do: nil

  defp days_since(nil), do: nil

  defp days_since(%DateTime{} = date) do
    now = DateTime.utc_now()
    diff_seconds = DateTime.diff(now, date)
    div(diff_seconds, 86_400)
  end

  defp normalize_integer(nil), do: nil
  defp normalize_integer(value) when is_integer(value), do: value

  defp normalize_integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {int, _} -> int
      _ -> nil
    end
  end

  defp normalize_integer(_), do: nil

  defp note_snippet(portfolio, repo_id) do
    case PortfolioManager.get_context(portfolio, repo_id) do
      {:ok, context} ->
        context.notes
        |> extract_first_line()
        |> truncate_notes()

      _ ->
        nil
    end
  end

  defp extract_first_line(nil), do: nil

  defp extract_first_line(notes) when is_binary(notes) do
    notes
    |> String.split("\n")
    |> Enum.map(&String.trim/1)
    |> Enum.find(&(&1 != ""))
  end

  defp truncate_notes(nil), do: nil

  defp truncate_notes(notes) do
    if String.length(notes) > 120 do
      String.slice(notes, 0, 117) <> "..."
    else
      notes
    end
  end
end
