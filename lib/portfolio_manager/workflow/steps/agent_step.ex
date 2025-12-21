defmodule PortfolioManager.Workflow.Steps.AgentStep do
  @moduledoc """
  Agent (LLM) execution step.

  Invokes the RAG agent for intelligent operations.
  """

  alias PortfolioManager.Workflow.Context

  @doc """
  Executes an agent step.

  ## Config Options

    * `query` - Question/prompt for the agent
    * `provider` - LLM provider to use (optional)
    * `capture` - Variable name to capture response into

  """
  @spec execute(map(), Context.t(), keyword()) ::
          {:ok, Context.t(), term()} | {:error, term()}
  def execute(step, context, opts) do
    config = step.config

    query =
      case config do
        q when is_binary(q) -> q
        %{"query" => q} -> q
        _ -> nil
      end

    if is_nil(query) do
      {:error, "No query specified"}
    else
      # Interpolate variables in query
      interpolated = Context.interpolate(context, query)

      portfolio = Keyword.get(opts, :portfolio)

      if is_nil(portfolio) do
        {:error, "Portfolio not available for agent step"}
      else
        execute_agent(interpolated, config, portfolio, context, step.name)
      end
    end
  end

  defp execute_agent(query, config, portfolio, context, step_name) do
    provider = get_provider(config)
    capture = get_capture(config)

    agent_opts = []
    agent_opts = if provider, do: Keyword.put(agent_opts, :provider, provider), else: agent_opts

    case PortfolioManager.query(portfolio, query, agent_opts) do
      {:ok, result} ->
        answer = Map.get(result, :answer, "")

        step_result = %{
          query: query,
          answer: answer,
          tools_used: Map.get(result, :tools_used, [])
        }

        new_ctx = Context.set_result(context, step_name, step_result)

        new_ctx =
          if capture do
            Context.set_var(new_ctx, capture, answer)
          else
            new_ctx
          end

        {:ok, new_ctx, step_result}

      {:error, reason} ->
        {:error, "Agent query failed: #{inspect(reason)}"}
    end
  end

  defp get_provider(config) when is_map(config) do
    case Map.get(config, "provider") do
      nil -> nil
      p when is_binary(p) -> String.to_atom(p)
      p -> p
    end
  end

  defp get_provider(_), do: nil

  defp get_capture(config) when is_map(config) do
    Map.get(config, "capture")
  end

  defp get_capture(_), do: nil
end
