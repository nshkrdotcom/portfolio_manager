defmodule Mix.Tasks.Portfolio.ShowTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureIO
  import PortfolioManager.TestHelpers

  setup do
    portfolio_path = create_test_portfolio()

    write_registry(portfolio_path)
    write_relationships(portfolio_path)
    write_context(portfolio_path)

    on_exit(fn -> cleanup_test_portfolio(portfolio_path) end)

    {:ok, portfolio_path: portfolio_path}
  end

  test "shows computed stats, dependencies, and relationships", %{portfolio_path: portfolio_path} do
    Mix.Task.reenable("portfolio.show")

    output =
      capture_io(fn ->
        Mix.Tasks.Portfolio.Show.run(["alpha", "--portfolio-dir", portfolio_path])
      end)

    assert output =~ "Commits (30d):"
    assert output =~ "Last commit:"
    assert output =~ "Dependencies (runtime):"
    assert output =~ "oban"
    assert output =~ "Relationships:"
    assert output =~ "beta"
  end

  test "outputs json with computed fields", %{portfolio_path: portfolio_path} do
    Mix.Task.reenable("portfolio.show")

    output =
      capture_io(fn ->
        Mix.Tasks.Portfolio.Show.run(["alpha", "--json", "--portfolio-dir", portfolio_path])
      end)

    data = Jason.decode!(output)
    assert data["repo"]["id"] == "alpha"
    assert data["computed"]["commit_count_30d"] == 5
  end

  defp write_registry(portfolio_path) do
    File.write!(
      Path.join(portfolio_path, "registry.yml"),
      """
      repos:
        - id: alpha
          name: Alpha
          path: /tmp/alpha
          type: library
          status: active
          language: elixir

        - id: beta
          name: Beta
          path: /tmp/beta
          type: application
          status: active
          language: elixir
      """
    )
  end

  defp write_relationships(portfolio_path) do
    File.write!(
      Path.join(portfolio_path, "relationships.yml"),
      """
      relationships:
        - from: beta
          to: alpha
          type: depends_on
      """
    )
  end

  defp write_context(portfolio_path) do
    repo_dir = Path.join([portfolio_path, "repos", "alpha"])
    File.mkdir_p!(repo_dir)

    File.write!(
      Path.join(repo_dir, "context.yml"),
      """
      id: alpha
      name: Alpha
      type: library
      status: active
      language: elixir
      computed:
        commit_count_30d: 5
        last_commit:
          sha: abc123
          date: 2025-01-01T00:00:00Z
          message: "Initial commit"
        contributors:
          - test@example.com
        dependencies:
          runtime:
            - oban
            - ecto
      """
    )
  end
end
