defmodule PortfolioManager.Adapters.LocalGit do
  @moduledoc """
  Local git adapter for repository operations.

  Uses system git commands for interacting with repositories.
  """

  @behaviour PortfolioManager.Ports.Git

  @impl true
  def is_repo?(path) do
    expanded = Path.expand(path)
    git_dir = Path.join(expanded, ".git")
    File.dir?(git_dir) or File.regular?(git_dir)
  end

  @impl true
  def get_info(path) do
    expanded = Path.expand(path)

    if is_repo?(expanded) do
      with {:ok, remote_url} <- get_remote_url(expanded),
           {:ok, branch} <- get_current_branch(expanded),
           {:ok, last_commit} <- get_last_commit(expanded),
           {:ok, last_commit_date} <- get_last_commit_date(expanded) do
        {:ok,
         %{
           path: expanded,
           remote_url: remote_url,
           branch: branch,
           last_commit: last_commit,
           last_commit_date: last_commit_date,
           is_dirty: is_dirty?(expanded)
         }}
      end
    else
      {:error, :not_a_repo}
    end
  end

  @impl true
  def get_remote_url(path) do
    case run_git(path, ["remote", "get-url", "origin"]) do
      {:ok, url} -> {:ok, String.trim(url)}
      {:error, _} -> {:ok, nil}
    end
  end

  @impl true
  def commit(path, message) do
    case run_git(path, ["commit", "-m", message]) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def add_all(path) do
    case run_git(path, ["add", "-A"]) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def is_dirty?(path) do
    case run_git(path, ["status", "--porcelain"]) do
      {:ok, ""} -> false
      {:ok, _} -> true
      {:error, _} -> false
    end
  end

  # Additional helpers

  @doc """
  Gets the current branch name.
  """
  @spec get_current_branch(String.t()) :: {:ok, String.t()} | {:error, term()}
  def get_current_branch(path) do
    case run_git(path, ["rev-parse", "--abbrev-ref", "HEAD"]) do
      {:ok, branch} -> {:ok, String.trim(branch)}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Gets the last commit hash (short).
  """
  @spec get_last_commit(String.t()) :: {:ok, String.t() | nil} | {:error, term()}
  def get_last_commit(path) do
    case run_git(path, ["rev-parse", "--short", "HEAD"]) do
      {:ok, hash} -> {:ok, String.trim(hash)}
      {:error, _} -> {:ok, nil}
    end
  end

  @doc """
  Gets the last commit date.
  """
  @spec get_last_commit_date(String.t()) :: {:ok, DateTime.t() | nil} | {:error, term()}
  def get_last_commit_date(path) do
    case run_git(path, ["log", "-1", "--format=%cI"]) do
      {:ok, date_str} ->
        date_str = String.trim(date_str)

        case DateTime.from_iso8601(date_str) do
          {:ok, dt, _} -> {:ok, dt}
          {:error, _} -> {:ok, nil}
        end

      {:error, _} ->
        {:ok, nil}
    end
  end

  @doc """
  Gets the last commit info (sha, date, message).
  """
  @spec last_commit_info(String.t()) :: {:ok, map() | nil} | {:error, term()}
  def last_commit_info(path) do
    case run_git(path, ["log", "-1", "--format=%H|%aI|%s"]) do
      {:ok, output} ->
        case String.trim(output) |> String.split("|", parts: 3) do
          [sha, date_str, message] ->
            date =
              case DateTime.from_iso8601(date_str) do
                {:ok, dt, _} -> dt
                {:error, _} -> nil
              end

            {:ok, %{sha: sha, date: date, message: message}}

          _ ->
            {:ok, nil}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Discovers git repositories in a directory.
  """
  @spec discover_repos(String.t(), keyword()) :: [String.t()]
  def discover_repos(path, opts \\ []) do
    expanded = Path.expand(path)
    max_depth = Keyword.get(opts, :max_depth, 3)
    exclude = Keyword.get(opts, :exclude, [])

    find_repos(expanded, max_depth, exclude, 0)
  end

  @doc """
  Gets the count of commits in the last 30 days.
  """
  @spec commit_count_30d(String.t()) :: {:ok, non_neg_integer()} | {:error, term()}
  def commit_count_30d(path) do
    case run_git(path, ["rev-list", "--count", "--since=30 days ago", "HEAD"]) do
      {:ok, count_str} ->
        count = count_str |> String.trim() |> String.to_integer()
        {:ok, count}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Fetches all remotes for a repository.
  """
  @spec fetch_all(String.t()) :: :ok | {:error, term()}
  def fetch_all(path) do
    case run_git(path, ["fetch", "--all", "--prune"]) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Gets the last commit info from the upstream branch.
  """
  @spec last_remote_commit_info(String.t()) :: {:ok, map() | nil} | {:error, term()}
  def last_remote_commit_info(path) do
    case run_git(path, ["log", "-1", "--format=%H|%aI|%s", "@{u}"]) do
      {:ok, output} ->
        case String.trim(output) |> String.split("|", parts: 3) do
          [sha, date_str, message] ->
            date =
              case DateTime.from_iso8601(date_str) do
                {:ok, dt, _} -> dt
                {:error, _} -> nil
              end

            {:ok, %{sha: sha, date: date, message: message}}

          _ ->
            {:ok, nil}
        end

      {:error, _} ->
        {:ok, nil}
    end
  end

  @doc """
  Gets the count of unique contributors.
  """
  @spec contributor_count(String.t()) :: {:ok, non_neg_integer()} | {:error, term()}
  def contributor_count(path) do
    case contributors(path) do
      {:ok, emails} -> {:ok, length(emails)}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Gets a list of contributors with commit counts.
  """
  @spec get_contributors(String.t()) :: {:ok, [map()]} | {:error, term()}
  def get_contributors(path) do
    case run_git(path, ["shortlog", "-sne", "HEAD"]) do
      {:ok, output} ->
        contributors =
          output
          |> String.split("\n")
          |> Enum.reject(&(&1 == ""))
          |> Enum.map(&parse_contributor_line/1)
          |> Enum.reject(&is_nil/1)

        {:ok, contributors}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Gets a list of contributor emails.
  """
  @spec contributors(String.t()) :: {:ok, [String.t()]} | {:error, term()}
  def contributors(path) do
    case get_contributors(path) do
      {:ok, contributors} ->
        emails =
          contributors
          |> Enum.map(&Map.get(&1, :email))
          |> Enum.reject(&is_nil/1)
          |> Enum.uniq()

        {:ok, emails}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Gets the date of the first commit.
  """
  @spec first_commit_date(String.t()) :: {:ok, DateTime.t() | nil} | {:error, term()}
  def first_commit_date(path) do
    case run_git(path, ["log", "--reverse", "--format=%cI"]) do
      {:ok, output} ->
        case output |> String.split("\n") |> List.first() do
          nil ->
            {:ok, nil}

          date_str ->
            case DateTime.from_iso8601(String.trim(date_str)) do
              {:ok, dt, _} -> {:ok, dt}
              {:error, _} -> {:ok, nil}
            end
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Gets the number of days since the last commit.
  """
  @spec days_since_last_commit(String.t()) :: {:ok, non_neg_integer()}
  def days_since_last_commit(path) do
    case get_last_commit_date(path) do
      {:ok, nil} ->
        {:ok, 0}

      {:ok, %DateTime{} = last_commit} ->
        now = DateTime.utc_now()
        diff_seconds = DateTime.diff(now, last_commit)
        days = div(diff_seconds, 86400)
        {:ok, days}
    end
  end

  # Private helpers

  defp parse_contributor_line(line) do
    # Parse lines like: "    42\tJohn Doe <john@example.com>"
    case Regex.run(~r/^\s*(\d+)\s+(.+?)\s+<(.+)>$/, line) do
      [_, count_str, name, email] ->
        %{
          name: String.trim(name),
          email: String.trim(email),
          commits: String.to_integer(count_str)
        }

      _ ->
        nil
    end
  end

  defp run_git(path, args) do
    case System.cmd("git", args, cd: path, stderr_to_stdout: true) do
      {output, 0} -> {:ok, output}
      {error, _code} -> {:error, String.trim(error)}
    end
  end

  defp find_repos(path, max_depth, exclude, current_depth) when current_depth <= max_depth do
    if is_repo?(path) do
      [path]
    else
      case File.ls(path) do
        {:ok, entries} ->
          entries
          |> Enum.filter(fn entry ->
            not String.starts_with?(entry, ".") and
              not Enum.any?(exclude, fn pattern ->
                matches_pattern?(entry, pattern)
              end)
          end)
          |> Enum.flat_map(fn entry ->
            full_path = Path.join(path, entry)

            if File.dir?(full_path) do
              find_repos(full_path, max_depth, exclude, current_depth + 1)
            else
              []
            end
          end)

        {:error, _} ->
          []
      end
    end
  end

  defp find_repos(_path, _max_depth, _exclude, _current_depth), do: []

  defp matches_pattern?(entry, pattern) do
    # Simple glob matching
    pattern =
      pattern
      |> String.replace("**/", "")
      |> String.replace("/**", "")
      |> String.replace("/", "")
      |> String.replace("*", ".*")

    case Regex.compile("^#{pattern}$") do
      {:ok, regex} -> Regex.match?(regex, entry)
      {:error, _} -> false
    end
  end
end
