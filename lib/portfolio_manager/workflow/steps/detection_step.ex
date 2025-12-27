defmodule PortfolioManager.Workflow.Steps.DetectionStep do
  @moduledoc """
  Detection step handlers.
  """

  alias PortfolioManager.Adapters.FileDetector
  alias PortfolioManager.Detection.Agentic
  alias PortfolioManager.Workflow.Context

  @spec execute(map(), Context.t(), keyword()) :: {:ok, Context.t(), term()} | {:error, term()}
  def execute(step, context, opts) do
    action = to_string(step.action || "")
    inputs = step.inputs || %{}
    portfolio = Keyword.get(opts, :portfolio)
    dispatch_action(action, inputs, portfolio, context)
  end

  defp dispatch_action("deterministic", inputs, _portfolio, context) do
    path = get_input(inputs, "path")
    run_deterministic(path, context)
  end

  defp dispatch_action("agentic", inputs, portfolio, context) do
    path = extract_agentic_path(inputs)
    run_agentic(path, portfolio, context)
  end

  defp dispatch_action(action, _inputs, _portfolio, _context) do
    {:error, "Unknown detection action: #{action}"}
  end

  defp extract_agentic_path(inputs) do
    repo = get_input(inputs, "repo")
    (repo && get_input(repo, "path")) || get_input(inputs, "path")
  end

  defp get_input(inputs, key) when is_map(inputs) do
    Map.get(inputs, key) || Map.get(inputs, String.to_atom(key))
  end

  defp get_input(_, _), do: nil

  defp run_deterministic(nil, _context), do: {:error, "path required"}

  defp run_deterministic(path, context) do
    {:ok, result} = FileDetector.detect(path)
    {:ok, context, %{result: result}}
  end

  defp run_agentic(nil, _portfolio, _context), do: {:error, "path required"}
  defp run_agentic(_path, nil, _context), do: {:error, "portfolio required"}

  defp run_agentic(path, portfolio, context) do
    {:ok, result} = Agentic.analyze(path, portfolio: portfolio)
    {:ok, context, %{result: result}}
  end
end
