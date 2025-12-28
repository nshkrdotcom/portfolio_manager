defmodule PortfolioManager.Repo do
  @moduledoc false

  use Ecto.Repo,
    otp_app: :portfolio_manager,
    adapter: Ecto.Adapters.Postgres
end
