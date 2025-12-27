defmodule Mix.Tasks.Portfolio.ReviewTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureIO
  import PortfolioManager.TestHelpers

  alias Mix.Tasks.Portfolio.Review
  alias PortfolioManager.Detection.ReviewStore

  test "accept-all applies updates and persists" do
    portfolio_path = create_test_portfolio()
    repo_path = Path.join(System.tmp_dir!(), "review_repo_#{:rand.uniform(1_000_000)}")

    create_test_repo(repo_path, name: "review_repo", language: :elixir)

    {:ok, portfolio} = PortfolioManager.init(portfolio_path)
    {:ok, repo} = PortfolioManager.add(portfolio, repo_path)
    :ok = PortfolioManager.sync(portfolio)

    item = %{
      "id" => "review_repo-status",
      "repo_id" => repo.id,
      "field" => "status",
      "value" => "maintenance",
      "confidence" => 0.95
    }

    :ok = ReviewStore.save_pending(portfolio_path, [item])

    on_exit(fn ->
      cleanup_test_portfolio(portfolio_path)
      cleanup_test_repo(repo_path)
    end)

    Mix.Task.reenable("portfolio.review")

    capture_io(fn ->
      Review.run([
        "--accept-all",
        "--threshold",
        "0.9",
        "--portfolio-dir",
        portfolio_path
      ])
    end)

    {:ok, portfolio_after} = PortfolioManager.init(portfolio_path)
    {:ok, context} = PortfolioManager.get_context(portfolio_after, repo.id)

    assert context.repo.status == :maintenance
  end
end
