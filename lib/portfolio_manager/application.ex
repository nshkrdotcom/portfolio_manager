defmodule PortfolioManager.Application do
  @moduledoc """
  Portfolio Manager OTP Application.

  Starts the supervision tree for the portfolio manager.
  """
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Registry for named portfolio instances
      {Registry, keys: :unique, name: PortfolioManager.Registry}
    ]

    opts = [strategy: :one_for_one, name: PortfolioManager.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
