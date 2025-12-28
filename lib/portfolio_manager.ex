defmodule PortfolioManager do
  @moduledoc """
  Application layer for managing code portfolios with RAG and graph tooling.
  """

  @version "0.2.0"

  @doc """
  Return the current library version.
  """
  @spec version() :: String.t()
  def version, do: @version
end
