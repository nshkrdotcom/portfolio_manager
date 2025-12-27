defmodule PortfolioManager.Workflow.Steps.AgentStep do
  @moduledoc """
  Agentic step handlers.
  """

  alias PortfolioManager.Workflow.Context

  @prompt_actions ~w(analyze generate classify extract)

  @spec execute(map(), Context.t(), keyword()) :: {:ok, Context.t(), term()} | {:error, term()}
  def execute(step, context, _opts) do
    action = to_string(step.action || "")
    inputs = step.inputs || %{}
    provider = get_provider(step, inputs)
    dispatch_action(action, inputs, provider, context)
  end

  defp dispatch_action(action, inputs, provider, context) when action in @prompt_actions do
    run_prompt(inputs, provider, context)
  end

  defp dispatch_action(action, _inputs, _provider, _context) do
    {:error, "Unknown agent action: #{action}"}
  end

  defp get_provider(step, inputs) do
    Map.get(step, :provider) || Map.get(inputs, "provider") || Map.get(inputs, :provider)
  end

  defp run_prompt(inputs, provider, context) do
    prompt = Map.get(inputs, "prompt") || Map.get(inputs, :prompt)

    if is_binary(prompt) do
      router_opts =
        if provider do
          [providers: [String.to_atom(to_string(provider))]]
        else
          []
        end

      with {:ok, router} <- PortfolioManager.Rag.create_router(router_opts),
           {:ok, response, _router} <- Rag.Router.execute(router, :text, prompt, []) do
        {:ok, context, %{output: response}}
      else
        {:error, reason} -> {:error, reason}
      end
    else
      {:error, "prompt required"}
    end
  end
end
