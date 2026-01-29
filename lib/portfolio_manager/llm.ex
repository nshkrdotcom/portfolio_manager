defmodule PortfolioManager.LLM do
  @moduledoc """
  LLM gateway backed by the configured PortfolioCore adapter registry.

  This module centralizes completion and streaming calls so manager flows
  always go through the configured LLM adapter.
  """

  @doc """
  Execute a completion using the configured LLM adapter.
  """
  @spec complete([map()], keyword()) :: {:ok, map()} | {:error, term()}
  def complete(messages, opts \\ []) when is_list(messages) do
    with {:ok, {adapter, adapter_opts}} <- resolve_adapter(),
         merged_opts <- Keyword.merge(adapter_opts, opts) do
      adapter.complete(messages, merged_opts)
    end
  end

  @doc """
  Stream a completion using the configured LLM adapter.
  """
  @spec stream([map()], keyword()) :: {:ok, Enumerable.t()} | {:error, term()}
  def stream(messages, opts \\ []) when is_list(messages) do
    with {:ok, {adapter, adapter_opts}} <- resolve_adapter(),
         merged_opts <- Keyword.merge(adapter_opts, opts),
         {:ok, stream} <- adapter.stream(messages, merged_opts) do
      {:ok, Stream.map(stream, &extract_delta/1)}
    end
  end

  defp resolve_adapter do
    case PortfolioCore.adapter(:llm) do
      {module, config} when is_atom(module) ->
        {:ok, {module, normalize_opts(config)}}

      _ ->
        {:error, :no_llm_adapter_configured}
    end
  end

  defp normalize_opts(opts) when is_list(opts), do: opts
  defp normalize_opts(opts) when is_map(opts), do: Map.to_list(opts)

  defp extract_delta(%{delta: delta}) when is_binary(delta), do: delta
  defp extract_delta(%{"delta" => delta}) when is_binary(delta), do: delta
  defp extract_delta(delta) when is_binary(delta), do: delta
  defp extract_delta(_), do: ""
end
