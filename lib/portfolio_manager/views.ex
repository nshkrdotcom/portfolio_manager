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
        case LocalGit.days_since_last_commit(repo.path) do
          {:ok, days} -> days >= stale_days
          _ -> false
        end
      end)
      |> Enum.map(fn repo ->
        {:ok, days} = LocalGit.days_since_last_commit(repo.path)
        {:ok, last_commit} = LocalGit.get_last_commit_date(repo.path)

        %{
          "id" => repo.id,
          "status" => to_string(repo.status),
          "days_since_commit" => days,
          "last_commit" => last_commit && DateTime.to_iso8601(last_commit),
          "recommendation" =>
            cond do
              days >= 180 -> "Consider archiving"
              days >= 90 -> "Mark as stale or maintenance"
              true -> "Review activity"
            end
        }
      end)
      |> Enum.sort_by(& &1["days_since_commit"], :desc)

    data = %{
      "generated_at" => DateTime.to_iso8601(DateTime.utc_now()),
      "query" => "days_since_commit >= #{stale_days}",
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

        %{
          "id" => repo.id,
          "upstream" => Map.get(port_info, :upstream, "unknown"),
          "synced_version" => Map.get(port_info, :synced_version, "unknown"),
          "language" => to_string(repo.language),
          "status" => to_string(repo.status)
        }
      end)

    data = %{
      "generated_at" => DateTime.to_iso8601(DateTime.utc_now()),
      "query" => "type == port",
      "results" => port_repos,
      "summary" => %{
        "total_ports" => length(port_repos)
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
end
