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
         :ok <- generate_stale_repos(portfolio, repos, opts),
         :ok <- generate_port_status(portfolio, repos) do
      :ok
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
      |> Enum.filter(fn repo ->
        computed = load_computed(portfolio, repo)
        commit_count = get_computed_value(computed, "commit_count_30d")
        last_commit_date = get_last_commit_date(repo, computed)
        days_since_commit = days_since(last_commit_date)

        cond do
          repo.status == :stale ->
            true

          repo.status == :active and commit_count == 0 ->
            true

          is_nil(commit_count) and is_integer(days_since_commit) ->
            days_since_commit >= stale_days

          true ->
            false
        end
      end)
      |> Enum.map(fn repo ->
        computed = load_computed(portfolio, repo)
        last_commit_date = get_last_commit_date(repo, computed)
        days = days_since(last_commit_date) || 0
        notes = note_snippet(portfolio, repo.id)

        base = %{
          "id" => repo.id,
          "status" => to_string(repo.status),
          "days_since_commit" => days,
          "last_commit" => last_commit_date && DateTime.to_iso8601(last_commit_date),
          "recommendation" =>
            cond do
              days >= 180 -> "Consider archiving"
              days >= 90 -> "Mark as stale or maintenance"
              true -> "Review activity"
            end
        }

        if notes do
          Map.put(base, "notes", notes)
        else
          base
        end
      end)
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

  @doc """
  Generates view of port repositories status.
  """
  @spec generate_port_status(GenServer.server(), [map()]) :: :ok | {:error, term()}
  def generate_port_status(portfolio, repos) do
    port_repos =
      repos
      |> Enum.filter(&(&1.type == :port))
      |> Enum.map(fn repo ->
        port_info = repo.port || %{}

        upstream =
          Map.get(port_info, :upstream_url) ||
            Map.get(port_info, "upstream_url") ||
            Map.get(port_info, :upstream) ||
            Map.get(port_info, "upstream") ||
            "unknown"

        upstream_version =
          Map.get(port_info, :upstream_version) ||
            Map.get(port_info, "upstream_version") ||
            get_in(port_info, [:sync, :last_tag]) ||
            get_in(port_info, ["sync", "last_tag"]) ||
            "unknown"

        synced_version =
          Map.get(port_info, :synced_version) ||
            Map.get(port_info, "synced_version") ||
            get_in(port_info, [:sync, :last_tag]) ||
            get_in(port_info, ["sync", "last_tag"]) ||
            "unknown"

        commits_behind =
          get_in(port_info, [:upstream_status, :commits_behind]) ||
            get_in(port_info, ["upstream_status", "commits_behind"]) ||
            Map.get(port_info, :commits_behind) ||
            Map.get(port_info, "commits_behind")

        commits_behind = normalize_integer(commits_behind)

        status =
          cond do
            is_integer(commits_behind) and commits_behind > 0 -> "needs_sync"
            is_integer(commits_behind) and commits_behind == 0 -> "up_to_date"
            true -> "unknown"
          end

        %{
          "id" => repo.id,
          "upstream" => to_string(upstream),
          "upstream_version" => to_string(upstream_version),
          "synced_version" => to_string(synced_version),
          "commits_behind" => commits_behind,
          "status" => status,
          "affected_modules" =>
            get_in(port_info, [:upstream_status, :affected_modules]) ||
              get_in(port_info, ["upstream_status", "affected_modules"]) ||
              get_in(port_info, [:sync, :affected_modules]) ||
              get_in(port_info, ["sync", "affected_modules"])
        }
      end)

    summary_counts =
      port_repos
      |> Enum.group_by(& &1["status"])
      |> Map.new(fn {k, v} -> {k, length(v)} end)

    total_commits_behind =
      port_repos
      |> Enum.map(& &1["commits_behind"])
      |> Enum.filter(&is_integer/1)
      |> Enum.sum()

    data = %{
      "generated_at" => DateTime.to_iso8601(DateTime.utc_now()),
      "query" => "type == port",
      "results" => port_repos,
      "summary" => %{
        "total_ports" => length(port_repos),
        "up_to_date" => Map.get(summary_counts, "up_to_date", 0),
        "needs_sync" => Map.get(summary_counts, "needs_sync", 0),
        "total_commits_behind" => total_commits_behind
      }
    }

    write_view(portfolio, "port-status.yml", data)
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

  defp do_yaml_encode(list, indent) when is_list(list) do
    if list == [] do
      "[]\n"
    else
      spaces = String.duplicate(" ", indent)

      list
      |> Enum.map(fn item ->
        item_str = do_yaml_encode(item, indent + 2) |> String.trim_trailing("\n")

        if is_map(item) do
          [first | rest] = String.split(item_str, "\n")
          first_line = "#{spaces}- #{first}"

          rest_lines =
            Enum.map(rest, fn line ->
              "#{spaces}  #{line}"
            end)

          Enum.join([first_line | rest_lines], "\n")
        else
          "#{spaces}- #{item_str}"
        end
      end)
      |> Enum.join("\n")
      |> Kernel.<>("\n")
    end
  end

  defp do_yaml_encode(map, indent) when is_map(map) do
    if map == %{} do
      "{}\n"
    else
      spaces = String.duplicate(" ", indent)

      map
      |> Enum.sort_by(fn {k, _} -> k end)
      |> Enum.map(fn {k, v} ->
        key = to_string(k)

        cond do
          is_map(v) and map_size(v) > 0 ->
            "#{spaces}#{key}:\n#{do_yaml_encode(v, indent + 2)}"

          is_list(v) and length(v) > 0 ->
            "#{spaces}#{key}:\n#{do_yaml_encode(v, indent + 2)}"

          true ->
            "#{spaces}#{key}: #{do_yaml_encode(v, indent) |> String.trim_leading()}"
        end
      end)
      |> Enum.join("")
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
