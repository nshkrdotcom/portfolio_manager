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
  Discovers git repositories in a directory.
  """
  @spec discover_repos(String.t(), keyword()) :: [String.t()]
  def discover_repos(path, opts \\ []) do
    expanded = Path.expand(path)
    max_depth = Keyword.get(opts, :max_depth, 3)
    exclude = Keyword.get(opts, :exclude, [])

    find_repos(expanded, max_depth, exclude, 0)
  end

  # Private helpers

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
    pattern = String.replace(pattern, "**/", "")
    pattern = String.replace(pattern, "*", ".*")

    case Regex.compile("^#{pattern}$") do
      {:ok, regex} -> Regex.match?(regex, entry)
      {:error, _} -> false
    end
  end
end
