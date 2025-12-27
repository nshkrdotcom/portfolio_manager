defmodule PortfolioManagerTest do
  use ExUnit.Case, async: true

  import PortfolioManager.TestHelpers

  describe "init/1" do
    test "creates and initializes portfolio" do
      path = Path.join(System.tmp_dir!(), "pm_init_#{:rand.uniform(10000)}")
      on_exit(fn -> File.rm_rf!(path) end)

      assert {:ok, portfolio} = PortfolioManager.init(path)
      assert is_pid(portfolio)

      # Verify it's working
      repos = PortfolioManager.list_repos(portfolio)
      assert repos == []
    end

    test "opens existing portfolio" do
      path = create_populated_portfolio()
      on_exit(fn -> cleanup_test_portfolio(path) end)

      assert {:ok, portfolio} = PortfolioManager.init(path)

      repos = PortfolioManager.list_repos(portfolio)
      assert length(repos) == 3
    end
  end

  describe "list_repos/2" do
    setup do
      path = create_populated_portfolio()
      {:ok, portfolio} = PortfolioManager.init(path)
      on_exit(fn -> cleanup_test_portfolio(path) end)
      %{portfolio: portfolio}
    end

    test "lists all repos", %{portfolio: portfolio} do
      repos = PortfolioManager.list_repos(portfolio)
      assert length(repos) == 3
    end

    test "filters by status", %{portfolio: portfolio} do
      repos = PortfolioManager.list_repos(portfolio, status: :active)
      assert length(repos) == 2
    end

    test "filters by type", %{portfolio: portfolio} do
      repos = PortfolioManager.list_repos(portfolio, type: :library)
      assert length(repos) == 1
    end

    test "filters by language", %{portfolio: portfolio} do
      repos = PortfolioManager.list_repos(portfolio, language: :elixir)
      assert length(repos) == 2
    end
  end

  describe "get_repo/2" do
    setup do
      path = create_populated_portfolio()
      {:ok, portfolio} = PortfolioManager.init(path)
      on_exit(fn -> cleanup_test_portfolio(path) end)
      %{portfolio: portfolio}
    end

    test "returns repo by id", %{portfolio: portfolio} do
      assert {:ok, repo} = PortfolioManager.get_repo(portfolio, "repo-a")
      assert repo.id == "repo-a"
      assert repo.name == "Repo A"
    end

    test "returns error for non-existent repo", %{portfolio: portfolio} do
      assert {:error, :not_found} = PortfolioManager.get_repo(portfolio, "non-existent")
    end
  end

  describe "get_context/2" do
    setup do
      path = create_populated_portfolio()
      {:ok, portfolio} = PortfolioManager.init(path)
      on_exit(fn -> cleanup_test_portfolio(path) end)
      %{portfolio: portfolio}
    end

    test "returns context for repo", %{portfolio: portfolio} do
      assert {:ok, context} = PortfolioManager.get_context(portfolio, "repo-a")
      assert context.repo.id == "repo-a"
    end

    test "returns error for non-existent repo", %{portfolio: portfolio} do
      assert {:error, :not_found} = PortfolioManager.get_context(portfolio, "missing")
    end
  end

  describe "search/3" do
    setup do
      path = create_populated_portfolio()
      {:ok, portfolio} = PortfolioManager.init(path)
      on_exit(fn -> cleanup_test_portfolio(path) end)
      %{portfolio: portfolio}
    end

    test "finds repos by name", %{portfolio: portfolio} do
      results = PortfolioManager.search(portfolio, "Repo A")
      assert length(results) == 1
      assert hd(results).id == "repo-a"
    end

    test "finds repos by id pattern", %{portfolio: portfolio} do
      results = PortfolioManager.search(portfolio, "repo-a")
      assert results != []
      assert Enum.any?(results, &(&1.id == "repo-a"))
    end

    test "is case insensitive", %{portfolio: portfolio} do
      results = PortfolioManager.search(portfolio, "REPO")
      assert length(results) == 3
    end
  end

  describe "get_relationships/2" do
    setup do
      path = create_populated_portfolio()
      {:ok, portfolio} = PortfolioManager.init(path)
      on_exit(fn -> cleanup_test_portfolio(path) end)
      %{portfolio: portfolio}
    end

    test "returns relationships for repo", %{portfolio: portfolio} do
      rels = PortfolioManager.get_relationships(portfolio, "repo-b")
      assert length(rels) == 1
      assert hd(rels).type == :depends_on
    end

    test "returns empty list for repo without relationships", %{portfolio: portfolio} do
      rels = PortfolioManager.get_relationships(portfolio, "repo-c")
      assert rels == []
    end
  end

  describe "add_relationship/4" do
    setup do
      path = create_populated_portfolio()
      {:ok, portfolio} = PortfolioManager.init(path)
      on_exit(fn -> cleanup_test_portfolio(path) end)
      %{portfolio: portfolio}
    end

    test "adds relationship", %{portfolio: portfolio} do
      assert {:ok, rel} =
               PortfolioManager.add_relationship(
                 portfolio,
                 "repo-c",
                 "upstream-lib",
                 :port_of
               )

      assert rel.from == "repo-c"
      assert rel.to == "upstream-lib"
      assert rel.type == :port_of

      # Verify it's persisted
      rels = PortfolioManager.get_relationships(portfolio, "repo-c")
      assert length(rels) == 1
    end
  end

  describe "status/1" do
    setup do
      path = create_populated_portfolio()
      {:ok, portfolio} = PortfolioManager.init(path)
      on_exit(fn -> cleanup_test_portfolio(path) end)
      %{portfolio: portfolio}
    end

    test "returns portfolio statistics", %{portfolio: portfolio} do
      stats = PortfolioManager.status(portfolio)

      assert stats.total == 3
      assert stats.by_status[:active] == 2
      assert stats.by_status[:stale] == 1
      assert stats.by_type[:library] == 1
      assert stats.by_type[:application] == 1
      assert stats.by_type[:port] == 1
    end
  end

  describe "sync/1" do
    setup do
      path = create_populated_portfolio()
      {:ok, portfolio} = PortfolioManager.init(path)
      on_exit(fn -> cleanup_test_portfolio(path) end)
      %{portfolio: portfolio, path: path}
    end

    test "saves current state", %{portfolio: portfolio, path: path} do
      # Get initial relationship count
      initial_rels = PortfolioManager.get_relationships(portfolio, "repo-a")
      initial_count = length(initial_rels)

      # Add a relationship
      {:ok, _} = PortfolioManager.add_relationship(portfolio, "repo-a", "repo-c", :related_to)

      # Sync to storage
      assert :ok = PortfolioManager.sync(portfolio)

      # Verify by creating new portfolio instance
      {:ok, portfolio2} = PortfolioManager.init(path)
      rels = PortfolioManager.get_relationships(portfolio2, "repo-a")
      assert length(rels) == initial_count + 1
    end
  end

  describe "remove/2" do
    setup do
      path = create_populated_portfolio()
      {:ok, portfolio} = PortfolioManager.init(path)
      on_exit(fn -> cleanup_test_portfolio(path) end)
      %{portfolio: portfolio}
    end

    test "removes repo from portfolio", %{portfolio: portfolio} do
      assert :ok = PortfolioManager.remove(portfolio, "repo-c")

      repos = PortfolioManager.list_repos(portfolio)
      assert length(repos) == 2
      refute Enum.any?(repos, &(&1.id == "repo-c"))
    end

    test "returns error for non-existent repo", %{portfolio: portfolio} do
      assert {:error, :not_found} = PortfolioManager.remove(portfolio, "missing")
    end
  end

  describe "semantic_search/3" do
    test "returns empty list (not implemented)" do
      path = create_test_portfolio()
      {:ok, portfolio} = PortfolioManager.init(path)
      on_exit(fn -> cleanup_test_portfolio(path) end)

      results = PortfolioManager.semantic_search(portfolio, "some query")
      assert results == []
    end
  end
end
