defmodule PortfolioManager.Adapters.YAMLStorageTest do
  use ExUnit.Case, async: true

  alias PortfolioManager.Adapters.YAMLStorage
  alias PortfolioManager.Domain.{Context, Registry, Repo}

  import PortfolioManager.TestHelpers

  setup do
    portfolio_path = create_test_portfolio()
    on_exit(fn -> cleanup_test_portfolio(portfolio_path) end)
    %{portfolio_path: portfolio_path}
  end

  describe "exists?/1" do
    test "returns true for initialized portfolio", %{portfolio_path: path} do
      assert YAMLStorage.exists?(path)
    end

    test "returns false for non-existent path" do
      refute YAMLStorage.exists?("/tmp/non_existent_#{:rand.uniform(10000)}")
    end

    test "returns false for directory without registry.yml" do
      tmp = System.tmp_dir!()
      dir = Path.join(tmp, "empty_dir_#{:rand.uniform(10000)}")
      File.mkdir_p!(dir)
      on_exit(fn -> File.rm_rf!(dir) end)

      refute YAMLStorage.exists?(dir)
    end
  end

  describe "create/1" do
    test "creates portfolio structure" do
      tmp = System.tmp_dir!()
      path = Path.join(tmp, "new_portfolio_#{:rand.uniform(10000)}")
      on_exit(fn -> File.rm_rf!(path) end)

      assert :ok = YAMLStorage.create(path)

      assert File.exists?(Path.join(path, "config.yml"))
      assert File.exists?(Path.join(path, "registry.yml"))
      assert File.exists?(Path.join(path, "relationships.yml"))
      assert File.dir?(Path.join(path, "repos"))
    end
  end

  describe "init/1" do
    test "initializes storage for existing portfolio", %{portfolio_path: path} do
      assert {:ok, state} = YAMLStorage.init(path)
      assert state.path == path
    end

    test "returns error for non-existent portfolio" do
      assert {:error, :not_initialized} = YAMLStorage.init("/tmp/non_existent")
    end
  end

  describe "load_registry/1" do
    test "loads empty registry", %{portfolio_path: path} do
      {:ok, state} = YAMLStorage.init(path)

      assert {:ok, registry} = YAMLStorage.load_registry(state)
      assert registry.repos == %{}
      assert registry.relationships == []
    end

    test "loads populated registry" do
      path = create_populated_portfolio()
      on_exit(fn -> cleanup_test_portfolio(path) end)

      {:ok, state} = YAMLStorage.init(path)
      {:ok, registry} = YAMLStorage.load_registry(state)

      assert map_size(registry.repos) == 3
      assert length(registry.relationships) == 1
    end
  end

  describe "save_registry/2" do
    test "saves registry to files", %{portfolio_path: path} do
      {:ok, state} = YAMLStorage.init(path)

      {:ok, repo} = Repo.new(%{id: "test-repo", type: :library})
      registry = Registry.new()
      {:ok, registry} = Registry.add_repo(registry, repo)

      assert :ok = YAMLStorage.save_registry(state, registry)

      # Verify by loading again
      {:ok, loaded} = YAMLStorage.load_registry(state)
      assert Map.has_key?(loaded.repos, "test-repo")
    end
  end

  describe "load_context/2" do
    test "loads context for repo" do
      path = create_populated_portfolio()
      on_exit(fn -> cleanup_test_portfolio(path) end)

      {:ok, state} = YAMLStorage.init(path)

      assert {:ok, context} = YAMLStorage.load_context(state, "repo-a")
      assert context.repo.id == "repo-a"
    end

    test "returns error for non-existent repo", %{portfolio_path: path} do
      {:ok, state} = YAMLStorage.init(path)

      assert {:error, :not_found} = YAMLStorage.load_context(state, "non-existent")
    end

    test "loads notes from separate file" do
      path = create_populated_portfolio()
      on_exit(fn -> cleanup_test_portfolio(path) end)

      # Add notes file
      notes_path = Path.join([path, "repos", "repo-a", "notes.md"])
      File.write!(notes_path, "# Notes\nSome notes here")

      {:ok, state} = YAMLStorage.init(path)
      {:ok, context} = YAMLStorage.load_context(state, "repo-a")

      assert context.notes == "# Notes\nSome notes here"
    end
  end

  describe "save_context/2" do
    test "saves context to files", %{portfolio_path: path} do
      {:ok, state} = YAMLStorage.init(path)

      {:ok, repo} = Repo.new(%{id: "new-repo", type: :library})
      context = Context.new(repo)
      context = %{context | notes: "Some notes", todos: ["Task 1"]}

      assert :ok = YAMLStorage.save_context(state, context)

      # Verify files exist
      repo_path = Path.join([path, "repos", "new-repo"])
      assert File.exists?(Path.join(repo_path, "context.yml"))
      assert File.exists?(Path.join(repo_path, "notes.md"))
    end

    test "creates repo directory if needed", %{portfolio_path: path} do
      {:ok, state} = YAMLStorage.init(path)

      {:ok, repo} = Repo.new(%{id: "brand-new-repo"})
      context = Context.new(repo)

      :ok = YAMLStorage.save_context(state, context)

      assert File.dir?(Path.join([path, "repos", "brand-new-repo"]))
    end
  end
end
