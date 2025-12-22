defmodule Mix.Tasks.Portfolio.ListTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureIO
  import PortfolioManager.TestHelpers

  setup do
    portfolio_path = create_test_portfolio()

    write_registry(portfolio_path)
    write_contexts(portfolio_path)

    on_exit(fn -> cleanup_test_portfolio(portfolio_path) end)

    {:ok, portfolio_path: portfolio_path}
  end

  test "filters by tag and sorts by last_commit", %{portfolio_path: portfolio_path} do
    Mix.Task.reenable("portfolio.list")

    output =
      capture_io(fn ->
        Mix.Tasks.Portfolio.List.run([
          "--tag",
          "core",
          "--sort",
          "last_commit",
          "--portfolio-dir",
          portfolio_path
        ])
      end)

    assert output =~ "alpha"
    assert output =~ "gamma"
    {alpha_idx, _} = :binary.match(output, "alpha")
    {gamma_idx, _} = :binary.match(output, "gamma")
    assert alpha_idx < gamma_idx
  end

  test "applies filter expression with json output and limit", %{portfolio_path: portfolio_path} do
    Mix.Task.reenable("portfolio.list")

    output =
      capture_io(fn ->
        Mix.Tasks.Portfolio.List.run([
          "status=active",
          "AND",
          "type=library",
          "--limit",
          "1",
          "--format",
          "json",
          "--portfolio-dir",
          portfolio_path
        ])
      end)

    data = Jason.decode!(output)
    assert length(data) == 1
    assert hd(data)["id"] == "alpha"
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
          tags: [core]

        - id: beta
          name: Beta
          path: /tmp/beta
          type: application
          status: active
          language: python
          tags: [app]

        - id: gamma
          name: Gamma
          path: /tmp/gamma
          type: library
          status: stale
          language: elixir
          tags: [core, legacy]
      """
    )
  end

  defp write_contexts(portfolio_path) do
    write_context(portfolio_path, "alpha", "2025-01-10T00:00:00Z")
    write_context(portfolio_path, "beta", "2025-02-01T00:00:00Z")
    write_context(portfolio_path, "gamma", "2024-12-01T00:00:00Z")
  end

  defp write_context(portfolio_path, repo_id, last_commit_date) do
    repo_dir = Path.join([portfolio_path, "repos", repo_id])
    File.mkdir_p!(repo_dir)

    File.write!(
      Path.join(repo_dir, "context.yml"),
      """
      id: #{repo_id}
      name: #{String.capitalize(repo_id)}
      type: library
      status: active
      language: elixir
      computed:
        last_commit:
          sha: abc123
          date: #{last_commit_date}
      """
    )
  end
end
