defmodule Mix.Tasks.Portfolio.AddTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureIO
  import PortfolioManager.TestHelpers

  test "persists added repo with overrides" do
    portfolio_path = create_test_portfolio()
    repo_path = Path.join(System.tmp_dir!(), "add_repo_#{:rand.uniform(1_000_000)}")

    create_test_repo(repo_path, name: "add_repo", language: :elixir)

    on_exit(fn ->
      cleanup_test_portfolio(portfolio_path)
      cleanup_test_repo(repo_path)
    end)

    Mix.Task.reenable("portfolio.add")

    capture_io(fn ->
      Mix.Tasks.Portfolio.Add.run([
        repo_path,
        "--id",
        "custom-repo",
        "--type",
        "library",
        "--portfolio-dir",
        portfolio_path
      ])
    end)

    {:ok, portfolio} = PortfolioManager.init(portfolio_path)
    {:ok, repo} = PortfolioManager.get_repo(portfolio, "custom-repo")

    assert repo.type == :library
    assert repo.path == Path.expand(repo_path)
  end
end
