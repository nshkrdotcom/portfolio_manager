defmodule Mix.Tasks.Portfolio.SyncTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureIO
  import PortfolioManager.TestHelpers

  alias Mix.Tasks.Portfolio.Sync

  test "sync writes computed git stats and dependencies" do
    portfolio_path = create_test_portfolio()
    on_exit(fn -> cleanup_test_portfolio(portfolio_path) end)
    repo_path = Path.join(portfolio_path, "sync_repo")

    create_test_repo(repo_path, name: "sync_repo", language: :elixir)

    # Add a framework dependency to ensure framework detection
    mix_path = Path.join(repo_path, "mix.exs")

    File.write!(mix_path, """
    defmodule SyncRepo.MixProject do
      use Mix.Project

      def project do
        [app: :sync_repo, version: "0.1.0", deps: deps()]
      end

      defp deps do
        [{:phoenix, "~> 1.7"}]
      end
    end
    """)

    System.cmd("git", ["add", "."], cd: repo_path)
    System.cmd("git", ["commit", "-m", "Add phoenix dep"], cd: repo_path)

    {:ok, portfolio} = PortfolioManager.init(portfolio_path)
    {:ok, repo} = PortfolioManager.add(portfolio, repo_path)
    :ok = PortfolioManager.sync(portfolio)

    Mix.Task.reenable("portfolio.sync")

    capture_io(fn ->
      Sync.run([repo.id, "--portfolio-dir", portfolio_path])
    end)

    {:ok, portfolio_after} = PortfolioManager.init(portfolio_path)
    {:ok, context} = PortfolioManager.get_context(portfolio_after, repo.id)
    computed = context.computed

    assert Map.has_key?(computed, "commit_count_30d")
    assert Map.has_key?(computed, "contributors")
    assert Map.has_key?(computed, "first_commit_date")
    assert Map.has_key?(computed, "last_commit")
    assert Map.has_key?(computed, "dependencies")
    assert context.repo.framework == "phoenix"

    deps = Map.get(computed, "dependencies")
    assert is_map(deps)
    assert "phoenix" in Map.get(deps, "runtime", [])

    contributors = Map.get(computed, "contributors")
    assert is_list(contributors)
    assert "test@test.com" in contributors
  end
end
