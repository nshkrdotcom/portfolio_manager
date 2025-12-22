defmodule PortfolioManager.Workflow.Steps.ShellStep do
  @moduledoc """
  Shell command steps.
  """

  alias PortfolioManager.Workflow.Context

  @spec execute(map(), Context.t(), keyword()) :: {:ok, Context.t(), term()} | {:error, term()}
  def execute(step, context, _opts) do
    action = to_string(step.action || "")
    inputs = step.inputs || %{}

    case action do
      "run" -> run_command(inputs, context)
      _ -> {:error, "Unknown shell action: #{action}"}
    end
  end

  defp run_command(inputs, context) do
    command = Map.get(inputs, "command") || Map.get(inputs, :command)

    if is_binary(command) do
      case System.cmd("sh", ["-c", command], stderr_to_stdout: true) do
        {output, 0} ->
          {:ok, context, %{stdout: output, stderr: "", exit_code: 0}}

        {output, code} ->
          {:ok, context, %{stdout: output, stderr: "", exit_code: code}}
      end
    else
      {:error, "command required"}
    end
  end
end
