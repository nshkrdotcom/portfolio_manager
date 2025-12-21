defmodule PortfolioManager.Workflow.Steps.GitStep do
  @moduledoc """
  Git command execution step.

  Supports various git operations on repositories.
  """

  alias PortfolioManager.Workflow.Context

  @doc """
  Executes a git step.

  ## Config Options

    * `command` - Git command to run (pull, push, fetch, status, etc.)
    * `args` - Additional arguments for the command
    * `path` - Repository path (defaults to context repo path)

  """
  @spec execute(map(), Context.t(), keyword()) ::
          {:ok, Context.t(), term()} | {:error, term()}
  def execute(step, context, _opts) do
    config = step.config

    path =
      case config do
        %{"path" => p} -> Context.interpolate(context, p)
        _ -> get_repo_path(context)
      end

    if is_nil(path) do
      {:error, "No repository path specified"}
    else
      command = Map.get(config, "command", "status")
      args = Map.get(config, "args", [])
      args = if is_binary(args), do: String.split(args), else: args

      execute_git(command, args, path, context, step.name)
    end
  end

  defp get_repo_path(context) do
    cond do
      context.repo -> context.repo.path
      Context.get_var(context, "repo_path") -> Context.get_var(context, "repo_path")
      true -> nil
    end
  end

  defp execute_git("status", _args, path, context, step_name) do
    case run_git(path, ["status", "--porcelain"]) do
      {:ok, output} ->
        is_dirty = output != ""
        result = %{dirty: is_dirty, output: output}
        new_ctx = Context.set_result(context, step_name, result)
        {:ok, new_ctx, result}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp execute_git("fetch", args, path, context, step_name) do
    full_args = ["fetch"] ++ args

    case run_git(path, full_args) do
      {:ok, output} ->
        result = %{output: output}
        new_ctx = Context.set_result(context, step_name, result)
        {:ok, new_ctx, result}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp execute_git("pull", args, path, context, step_name) do
    full_args = ["pull"] ++ args

    case run_git(path, full_args) do
      {:ok, output} ->
        result = %{output: output}
        new_ctx = Context.set_result(context, step_name, result)
        {:ok, new_ctx, result}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp execute_git("push", args, path, context, step_name) do
    full_args = ["push"] ++ args

    case run_git(path, full_args) do
      {:ok, output} ->
        result = %{output: output}
        new_ctx = Context.set_result(context, step_name, result)
        {:ok, new_ctx, result}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp execute_git("log", args, path, context, step_name) do
    full_args = ["log"] ++ args

    case run_git(path, full_args) do
      {:ok, output} ->
        result = %{output: output}
        new_ctx = Context.set_result(context, step_name, result)
        {:ok, new_ctx, result}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp execute_git("diff", args, path, context, step_name) do
    full_args = ["diff"] ++ args

    case run_git(path, full_args) do
      {:ok, output} ->
        has_diff = output != ""
        result = %{has_diff: has_diff, output: output}
        new_ctx = Context.set_result(context, step_name, result)
        {:ok, new_ctx, result}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp execute_git("commit", args, path, context, step_name) do
    # Ensure there's a message
    args =
      if Enum.any?(args, &String.starts_with?(&1, "-m")) do
        args
      else
        ["-m", "Automated commit"] ++ args
      end

    full_args = ["commit"] ++ args

    case run_git(path, full_args) do
      {:ok, output} ->
        result = %{output: output}
        new_ctx = Context.set_result(context, step_name, result)
        {:ok, new_ctx, result}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp execute_git("add", args, path, context, step_name) do
    full_args = ["add"] ++ args

    case run_git(path, full_args) do
      {:ok, output} ->
        result = %{output: output}
        new_ctx = Context.set_result(context, step_name, result)
        {:ok, new_ctx, result}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp execute_git("remote", args, path, context, step_name) do
    full_args = ["remote"] ++ args

    case run_git(path, full_args) do
      {:ok, output} ->
        result = %{output: String.trim(output)}
        new_ctx = Context.set_result(context, step_name, result)
        {:ok, new_ctx, result}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp execute_git(command, args, path, context, step_name) do
    full_args = [command] ++ args

    case run_git(path, full_args) do
      {:ok, output} ->
        result = %{command: command, output: output}
        new_ctx = Context.set_result(context, step_name, result)
        {:ok, new_ctx, result}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp run_git(path, args) do
    case System.cmd("git", args, cd: path, stderr_to_stdout: true) do
      {output, 0} -> {:ok, output}
      {error, _code} -> {:error, String.trim(error)}
    end
  end
end
