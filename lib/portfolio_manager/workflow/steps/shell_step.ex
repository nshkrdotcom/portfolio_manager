defmodule PortfolioManager.Workflow.Steps.ShellStep do
  @moduledoc """
  Shell command execution step.

  Executes shell commands with variable interpolation.
  """

  alias PortfolioManager.Workflow.Context

  @doc """
  Executes a shell step.

  ## Config Options

    * `command` - Shell command to execute
    * `cwd` - Working directory (defaults to repo path or current dir)
    * `env` - Environment variables to set
    * `capture` - Variable name to capture output into

  """
  @spec execute(map(), Context.t(), keyword()) ::
          {:ok, Context.t(), term()} | {:error, term()}
  def execute(step, context, _opts) do
    config = step.config

    command =
      case config do
        cmd when is_binary(cmd) -> cmd
        %{"command" => cmd} -> cmd
        _ -> nil
      end

    if is_nil(command) do
      {:error, "No command specified"}
    else
      # Interpolate variables in command
      interpolated = Context.interpolate(context, command)

      cwd = get_cwd(config, context)
      env = get_env(config, context)
      capture = get_capture(config)

      execute_command(interpolated, cwd, env, capture, context, step.name)
    end
  end

  defp get_cwd(config, context) when is_map(config) do
    case Map.get(config, "cwd") do
      nil -> get_default_cwd(context)
      path -> Context.interpolate(context, path)
    end
  end

  defp get_cwd(_config, context) do
    get_default_cwd(context)
  end

  defp get_default_cwd(context) do
    cond do
      context.repo && context.repo.path -> context.repo.path
      true -> File.cwd!()
    end
  end

  defp get_env(config, context) when is_map(config) do
    base_env = Map.get(context.env, "env", %{})

    config_env =
      config
      |> Map.get("env", %{})
      |> Enum.map(fn {k, v} -> {to_string(k), Context.interpolate(context, to_string(v))} end)
      |> Map.new()

    Map.merge(base_env, config_env)
    |> Enum.map(fn {k, v} -> {to_charlist(k), to_charlist(v)} end)
  end

  defp get_env(_config, _context), do: []

  defp get_capture(config) when is_map(config) do
    Map.get(config, "capture")
  end

  defp get_capture(_config), do: nil

  defp execute_command(command, cwd, env, capture, context, step_name) do
    opts = [cd: cwd, stderr_to_stdout: true]
    opts = if env != [], do: Keyword.put(opts, :env, env), else: opts

    # Use sh -c to execute the command string
    case System.cmd("sh", ["-c", command], opts) do
      {output, 0} ->
        result = %{
          output: String.trim(output),
          exit_code: 0
        }

        new_ctx = Context.set_result(context, step_name, result)

        new_ctx =
          if capture do
            Context.set_var(new_ctx, capture, String.trim(output))
          else
            new_ctx
          end

        {:ok, new_ctx, result}

      {output, code} ->
        {:error, "Command failed with exit code #{code}: #{String.trim(output)}"}
    end
  end
end
