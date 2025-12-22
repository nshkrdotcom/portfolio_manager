defmodule PortfolioManager.Cache.SQLiteTest do
  use ExUnit.Case, async: true

  import PortfolioManager.TestHelpers

  alias PortfolioManager.Cache.SQLite

  setup do
    unless SQLite.available?() do
      {:skip, "exqlite not available"}
    end

    portfolio_path = create_test_portfolio()

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
      """
    )

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
      purpose: "UniqueSearchTerm library"
      """
    )

    File.write!(
      Path.join(repo_dir, "notes.md"),
      """
      Notes mention unique_term for search.
      """
    )

    on_exit(fn -> cleanup_test_portfolio(portfolio_path) end)

    {:ok, portfolio_path: portfolio_path}
  end

  test "build_index creates fts and search works", %{portfolio_path: portfolio_path} do
    assert :ok = SQLite.build_index(portfolio_path)

    {:ok, cache} = SQLite.start_link(portfolio_path: portfolio_path)

    assert File.exists?(Path.join([portfolio_path, ".portfolio", "cache", "index.db"]))

    {:ok, results} = SQLite.search(cache, "unique_term")
    assert Enum.any?(results, &(&1.id == "alpha"))

    GenServer.stop(cache)
  end
end
