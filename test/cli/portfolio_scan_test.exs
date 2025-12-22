defmodule Mix.Tasks.Portfolio.ScanTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureIO
  import PortfolioManager.TestHelpers

  test "uses configured scan directories when none provided" do
    portfolio_path = create_test_portfolio()
    scan_dir = Path.join(System.tmp_dir!(), "scan_dir_#{:rand.uniform(1_000_000)}")
    repo_path = Path.join(scan_dir, "config_repo")

    create_test_repo(repo_path, name: "config_repo", language: :elixir)

    File.write!(
      Path.join(portfolio_path, "config.yml"),
      """
      version: "1.0"
      scan:
        directories:
          - #{scan_dir}
      """
    )

    on_exit(fn ->
      cleanup_test_portfolio(portfolio_path)
      File.rm_rf!(scan_dir)
    end)

    Mix.Task.reenable("portfolio.scan")

    capture_io(fn ->
      Mix.Tasks.Portfolio.Scan.run(["--portfolio-dir", portfolio_path])
    end)

    {:ok, portfolio} = PortfolioManager.init(portfolio_path)
    repos = PortfolioManager.list_repos(portfolio)

    assert Enum.any?(repos, &(&1.id == "config_repo"))
  end

  test "respects exclude_patterns from config" do
    portfolio_path = create_test_portfolio()
    scan_dir = Path.join(System.tmp_dir!(), "scan_exclude_#{:rand.uniform(1_000_000)}")
    keep_repo = Path.join(scan_dir, "keep_repo")
    skip_repo = Path.join(scan_dir, "skip_repo")

    create_test_repo(keep_repo, name: "keep_repo", language: :elixir)
    create_test_repo(skip_repo, name: "skip_repo", language: :elixir)

    File.write!(
      Path.join(portfolio_path, "config.yml"),
      """
      version: "1.0"
      scan:
        directories:
          - #{scan_dir}
        exclude_patterns:
          - "**/skip_repo/**"
      """
    )

    on_exit(fn ->
      cleanup_test_portfolio(portfolio_path)
      File.rm_rf!(scan_dir)
    end)

    Mix.Task.reenable("portfolio.scan")

    capture_io(fn ->
      Mix.Tasks.Portfolio.Scan.run(["--portfolio-dir", portfolio_path])
    end)

    {:ok, portfolio} = PortfolioManager.init(portfolio_path)
    repos = PortfolioManager.list_repos(portfolio)

    assert Enum.any?(repos, &(&1.id == "keep_repo"))
    refute Enum.any?(repos, &(&1.id == "skip_repo"))
  end
end
