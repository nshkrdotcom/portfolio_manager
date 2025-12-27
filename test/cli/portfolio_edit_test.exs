defmodule Mix.Tasks.Portfolio.EditTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureIO
  import PortfolioManager.TestHelpers

  alias Mix.Tasks.Portfolio.Edit

  setup do
    portfolio_path = create_test_portfolio()
    repo_path = Path.join(System.tmp_dir!(), "edit_repo_#{:rand.uniform(1_000_000)}")

    create_test_repo(repo_path, name: "edit_repo", language: :elixir)

    {:ok, portfolio} = PortfolioManager.init(portfolio_path)
    {:ok, repo} = PortfolioManager.add(portfolio, repo_path)
    :ok = PortfolioManager.sync(portfolio)

    on_exit(fn ->
      cleanup_test_portfolio(portfolio_path)
      cleanup_test_repo(repo_path)
    end)

    {:ok, portfolio_path: portfolio_path, repo_id: repo.id}
  end

  test "updates fields with --set", %{portfolio_path: portfolio_path, repo_id: repo_id} do
    Mix.Task.reenable("portfolio.edit")

    capture_io(fn ->
      Edit.run([
        repo_id,
        "--set",
        "status=stale",
        "--portfolio-dir",
        portfolio_path
      ])
    end)

    {:ok, portfolio} = PortfolioManager.init(portfolio_path)
    {:ok, context} = PortfolioManager.get_context(portfolio, repo_id)

    assert context.repo.status == :stale
  end
end
