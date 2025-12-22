defmodule PortfolioManager.InitTest do
  use ExUnit.Case, async: false

  import PortfolioManager.TestHelpers

  test "init/0 respects PORTFOLIO_DIR" do
    portfolio_path = create_test_portfolio()

    System.put_env("PORTFOLIO_DIR", portfolio_path)

    on_exit(fn ->
      System.delete_env("PORTFOLIO_DIR")
      cleanup_test_portfolio(portfolio_path)
    end)

    {:ok, portfolio} = PortfolioManager.init()
    state = PortfolioManager.Portfolio.get_storage_state(portfolio)

    assert state.path == Path.expand(portfolio_path)
  end
end
