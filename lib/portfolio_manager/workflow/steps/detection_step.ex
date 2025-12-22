defmodule PortfolioManager.Workflow.Steps.DetectionStep do
  @moduledoc """
  Detection step handlers.
  """

  alias PortfolioManager.Workflow.Context
  alias PortfolioManager.Adapters.FileDetector
  alias PortfolioManager.Detection.Agentic

  @spec execute(map(), Context.t(), keyword()) :: {:ok, Context.t(), term()} | {:error, term()}
  def execute(step, context, opts) do
    action = to_string(step.action || "")
    inputs = step.inputs || %{}
    portfolio = Keyword.get(opts, :portfolio)

    case action do
      "deterministic" ->
        path = Map.get(inputs, "path") || Map.get(inputs, :path)
        run_deterministic(path, context)

      "agentic" ->
        repo = Map.get(inputs, "repo") || Map.get(inputs, :repo)
        path = Map.get(repo, "path") || Map.get(repo, :path) || Map.get(inputs, "path")
        run_agentic(path, portfolio, context)

      _ ->
        {:error, "Unknown detection action: #{action}"}
    end
  end

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
