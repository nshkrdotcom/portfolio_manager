defmodule PortfolioManager.LLM do
  @moduledoc """
  LLM gateway built on nsai_llm Actions and the PortfolioCore adapter registry.

  This module centralizes completion and streaming calls so manager flows
  always go through the configured LLM adapter.
  """

  alias Jido.Exec
  alias NSAI.LLM.Actions.Complete
  alias NSAI.LLM.Actions.Stream, as: LLMStream

  @doc """
  Execute a completion using the configured LLM adapter.
  """
  @spec complete([map()], keyword()) :: {:ok, map()} | {:error, term()}
  def complete(messages, opts \\ []) when is_list(messages) do
    params = %{messages: messages, opts: opts}

    case Exec.run(Complete, params, %{}) do
      {:ok, completion} ->
        {:ok, normalize_completion(completion)}

      {:error, reason} ->
        {:error, normalize_error(reason)}
    end
  end

  @doc """
  Stream a completion using the configured LLM adapter.
  """
  @spec stream([map()], keyword()) :: {:ok, Enumerable.t()} | {:error, term()}
  def stream(messages, opts \\ []) when is_list(messages) do
    params = %{messages: messages, opts: opts}

    case Exec.run(LLMStream, params, %{}) do
      {:ok, %{stream: stream}} ->
        {:ok, Stream.map(stream, &extract_content/1)}

      {:error, reason} ->
        {:error, normalize_error(reason)}
    end
  end

  defp normalize_completion(completion) do
    %{
      content: extract_content(completion),
      usage: Map.get(completion, :usage) || Map.get(completion, "usage"),
      model: Map.get(completion, :model) || Map.get(completion, "model"),
      completion: completion
    }
  end

  defp extract_content(completion) when is_map(completion) do
    completion
    |> Map.get(:choices, Map.get(completion, "choices", []))
    |> List.first()
    |> case do
      %{message: %{content: content}} -> content
      %{"message" => %{"content" => content}} -> content
      _ -> ""
    end
  end

  defp extract_content(_), do: ""

  @dialyzer {:nowarn_function, normalize_error: 1}
  defp normalize_error(error) do
    if is_map(error) and Map.has_key?(error, :__struct__) do
      case Map.get(error, :message) do
        message when is_binary(message) or is_atom(message) -> message
        _ -> error
      end
    else
      error
    end
  end
end
