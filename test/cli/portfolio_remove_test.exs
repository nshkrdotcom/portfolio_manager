defmodule Mix.Tasks.Portfolio.RemoveTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureIO
  import PortfolioManager.TestHelpers

  test "removes repo and optionally keeps docs" do
    portfolio_path = create_test_portfolio()
    repo1_path = Path.join(System.tmp_dir!(), "remove_repo1_#{:rand.uniform(1_000_000)}")
    repo2_path = Path.join(System.tmp_dir!(), "remove_repo2_#{:rand.uniform(1_000_000)}")

    create_test_repo(repo1_path, name: "remove_repo1", language: :elixir)
    create_test_repo(repo2_path, name: "remove_repo2", language: :elixir)

    {:ok, portfolio} = PortfolioManager.init(portfolio_path)
    {:ok, repo1} = PortfolioManager.add(portfolio, repo1_path)
    {:ok, repo2} = PortfolioManager.add(portfolio, repo2_path)
    :ok = PortfolioManager.sync(portfolio)

    on_exit(fn ->
      cleanup_test_portfolio(portfolio_path)
      cleanup_test_repo(repo1_path)
      cleanup_test_repo(repo2_path)
    end)

    Mix.Task.reenable("portfolio.remove")

    capture_io(fn ->
      Mix.Tasks.Portfolio.Remove.run([
        repo1.id,
        "--force",
        "--keep-docs",
        "--portfolio-dir",
        portfolio_path
      ])
    end)

    Mix.Task.reenable("portfolio.remove")

    capture_io(fn ->
      Mix.Tasks.Portfolio.Remove.run([
        repo2.id,
        "--force",
        "--portfolio-dir",
        portfolio_path
      ])
    end)

    {:ok, portfolio_after} = PortfolioManager.init(portfolio_path)
    repos = PortfolioManager.list_repos(portfolio_after)

    refute Enum.any?(repos, &(&1.id == repo1.id))
    refute Enum.any?(repos, &(&1.id == repo2.id))

    assert File.dir?(Path.join([portfolio_path, "repos", repo1.id]))
    refute File.dir?(Path.join([portfolio_path, "repos", repo2.id]))
  end
end
