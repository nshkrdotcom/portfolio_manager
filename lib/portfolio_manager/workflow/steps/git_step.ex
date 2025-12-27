defmodule PortfolioManager.Workflow.Steps.GitStep do
  @moduledoc """
  Git operation steps.
  """

  alias PortfolioManager.Workflow.Context

  @spec execute(map(), Context.t(), keyword()) :: {:ok, Context.t(), term()} | {:error, term()}
  def execute(step, context, _opts) do
    action = to_string(step.action || "")
    inputs = step.inputs || %{}
    repo_path = get_input(inputs, "path") || (context.repo && context.repo.path)
    dispatch_action(action, repo_path, inputs, context)
  end

  defp dispatch_action("fetch", repo_path, inputs, context),
    do: git_fetch(repo_path, inputs, context)

  defp dispatch_action("diff", repo_path, inputs, context),
    do: git_diff(repo_path, inputs, context)

  defp dispatch_action("log", repo_path, inputs, context), do: git_log(repo_path, inputs, context)
  defp dispatch_action("clone", _repo_path, inputs, context), do: git_clone(inputs, context)

  defp dispatch_action(action, _repo_path, _inputs, _context),
    do: {:error, "Unknown git action: #{action}"}

  defp get_input(inputs, key), do: Map.get(inputs, key) || Map.get(inputs, String.to_atom(key))

  defp git_fetch(nil, _inputs, _context), do: {:error, "repo path required"}

  defp git_fetch(path, inputs, context) do
    url = Map.get(inputs, "url") || Map.get(inputs, :url)
    args = if url, do: ["fetch", url], else: ["fetch"]

    case run_git(path, args) do
      {:ok, _} -> {:ok, context, %{fetched: true}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp git_diff(nil, _inputs, _context), do: {:error, "repo path required"}

  defp git_diff(path, inputs, context) do
    base = Map.get(inputs, "base") || Map.get(inputs, :base)
    head = Map.get(inputs, "head") || Map.get(inputs, :head) || "HEAD"

    args =
      if base do
        ["rev-list", "--count", "#{base}..#{head}"]
      else
        ["rev-list", "--count", head]
      end

    case run_git(path, args) do
      {:ok, output} ->
        count =
          output
          |> String.trim()
          |> Integer.parse()
          |> case do
            {int, _} -> int
            _ -> 0
          end

        {:ok, context, %{commit_count: count, file_count: 0, changed_files: []}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp git_log(nil, _inputs, _context), do: {:error, "repo path required"}

  defp git_log(path, inputs, context) do
    limit = Map.get(inputs, "limit") || Map.get(inputs, :limit) || 10

    case run_git(path, ["log", "-n", to_string(limit), "--format=%H|%s"]) do
      {:ok, output} ->
        commits =
          output
          |> String.split("\n", trim: true)
          |> Enum.map(&parse_commit_line/1)
          |> Enum.reject(&is_nil/1)

        {:ok, context, %{commits: commits}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp parse_commit_line(line) do
    case String.split(line, "|", parts: 2) do
      [sha, msg] -> %{sha: sha, message: msg}
      _ -> nil
    end
  end

  defp git_clone(inputs, context) do
    url = Map.get(inputs, "url") || Map.get(inputs, :url)
    dest = Map.get(inputs, "dest") || Map.get(inputs, :dest)

    cond do
      is_nil(url) ->
        {:error, "url required"}

      is_nil(dest) ->
        {:error, "dest required"}

      true ->
        case System.cmd("git", ["clone", url, dest], stderr_to_stdout: true) do
          {_output, 0} -> {:ok, context, %{cloned: true, path: dest}}
          {output, _} -> {:error, String.trim(output)}
        end
    end
  end

  defp run_git(path, args) do
    case System.cmd("git", args, cd: path, stderr_to_stdout: true) do
      {output, 0} -> {:ok, output}
      {error, _} -> {:error, String.trim(error)}
    end
  end
end
