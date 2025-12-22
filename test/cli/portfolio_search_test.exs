defmodule Mix.Tasks.Portfolio.SearchTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureIO
  import PortfolioManager.TestHelpers

  setup do
    portfolio_path = create_test_portfolio()

    File.write!(
      Path.join(portfolio_path, "registry.yml"),
      """
      repos:
        - id: alpha
          name: Alpha Repo
          path: /tmp/alpha
          type: library
          status: active

        - id: beta
          name: Beta Repo
          path: /tmp/beta
          type: application
          status: active
      """
    )

    on_exit(fn -> cleanup_test_portfolio(portfolio_path) end)

    {:ok, portfolio_path: portfolio_path}
  end

  test "supports regex search", %{portfolio_path: portfolio_path} do
    Mix.Task.reenable("portfolio.search")

    output =
      capture_io(fn ->
        Mix.Tasks.Portfolio.Search.run([
          "^alp",
          "--regex",
          "--portfolio-dir",
          portfolio_path
        ])
      end)

    assert output =~ "alpha"
  end

  test "supports field filtering with json output", %{portfolio_path: portfolio_path} do
    Mix.Task.reenable("portfolio.search")

    output =
      capture_io(fn ->
        Mix.Tasks.Portfolio.Search.run([
          "beta",
          "--field",
          "id",
          "--json",
          "--portfolio-dir",
          portfolio_path
        ])
      end)

    data = Jason.decode!(output)
    assert length(data) == 1
    assert hd(data)["id"] == "beta"
  end
end
