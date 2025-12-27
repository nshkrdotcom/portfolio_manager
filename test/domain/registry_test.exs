defmodule PortfolioManager.Domain.RegistryTest do
  use ExUnit.Case, async: true

  alias PortfolioManager.Domain.{Registry, Relationship, Repo}

  describe "new/0" do
    test "creates empty registry" do
      registry = Registry.new()

      assert registry.repos == %{}
      assert registry.relationships == []
    end
  end

  describe "from_data/2" do
    test "loads repos and relationships from data" do
      repos_data = [
        %{"id" => "repo-a", "type" => "library", "status" => "active"},
        %{"id" => "repo-b", "type" => "application", "status" => "active"}
      ]

      rels_data = [
        %{"from" => "repo-b", "to" => "repo-a", "type" => "depends_on"}
      ]

      assert {:ok, registry} = Registry.from_data(repos_data, rels_data)
      assert map_size(registry.repos) == 2
      assert length(registry.relationships) == 1
    end

    test "returns error for invalid repo data" do
      repos_data = [%{"name" => "no id"}]

      assert {:error, :id_required} = Registry.from_data(repos_data, [])
    end

    test "returns error for invalid relationship data" do
      repos_data = [%{"id" => "repo-a"}]
      # missing 'to'
      rels_data = [%{"from" => "a"}]

      assert {:error, :to_required} = Registry.from_data(repos_data, rels_data)
    end
  end

  describe "add_repo/2" do
    test "adds repo to registry" do
      registry = Registry.new()
      {:ok, repo} = Repo.new(%{id: "my-repo"})

      assert {:ok, updated} = Registry.add_repo(registry, repo)
      assert Map.has_key?(updated.repos, "my-repo")
    end

    test "rejects duplicate repo" do
      registry = Registry.new()
      {:ok, repo} = Repo.new(%{id: "my-repo"})

      {:ok, registry} = Registry.add_repo(registry, repo)

      assert {:error, :already_exists} = Registry.add_repo(registry, repo)
    end
  end

  describe "update_repo/3" do
    test "updates existing repo" do
      registry = Registry.new()
      {:ok, repo} = Repo.new(%{id: "my-repo", type: :unknown})
      {:ok, registry} = Registry.add_repo(registry, repo)

      assert {:ok, updated} = Registry.update_repo(registry, "my-repo", %{type: :library})
      assert updated.repos["my-repo"].type == :library
    end

    test "returns error for non-existent repo" do
      registry = Registry.new()

      assert {:error, :not_found} = Registry.update_repo(registry, "missing", %{})
    end
  end

  describe "remove_repo/2" do
    test "removes repo from registry" do
      registry = Registry.new()
      {:ok, repo} = Repo.new(%{id: "my-repo"})
      {:ok, registry} = Registry.add_repo(registry, repo)

      assert {:ok, updated} = Registry.remove_repo(registry, "my-repo")
      refute Map.has_key?(updated.repos, "my-repo")
    end

    test "removes associated relationships" do
      registry = Registry.new()
      {:ok, repo_a} = Repo.new(%{id: "repo-a"})
      {:ok, repo_b} = Repo.new(%{id: "repo-b"})
      {:ok, registry} = Registry.add_repo(registry, repo_a)
      {:ok, registry} = Registry.add_repo(registry, repo_b)

      {:ok, rel} = Relationship.new(%{from: "repo-b", to: "repo-a", type: :depends_on})
      {:ok, registry} = Registry.add_relationship(registry, rel)

      {:ok, updated} = Registry.remove_repo(registry, "repo-a")
      assert updated.relationships == []
    end

    test "returns error for non-existent repo" do
      registry = Registry.new()

      assert {:error, :not_found} = Registry.remove_repo(registry, "missing")
    end
  end

  describe "get_repo/2" do
    test "returns repo by id" do
      registry = Registry.new()
      {:ok, repo} = Repo.new(%{id: "my-repo", name: "My Repo"})
      {:ok, registry} = Registry.add_repo(registry, repo)

      assert {:ok, found} = Registry.get_repo(registry, "my-repo")
      assert found.name == "My Repo"
    end

    test "returns error for non-existent repo" do
      registry = Registry.new()

      assert {:error, :not_found} = Registry.get_repo(registry, "missing")
    end
  end

  describe "list_repos/2" do
    setup do
      registry = Registry.new()

      repos = [
        %{id: "lib-1", type: :library, status: :active, language: :elixir, tags: ["core"]},
        %{id: "lib-2", type: :library, status: :stale, language: :elixir, tags: []},
        %{id: "app-1", type: :application, status: :active, language: :python, tags: ["ai"]}
      ]

      registry =
        Enum.reduce(repos, registry, fn attrs, reg ->
          {:ok, repo} = Repo.new(attrs)
          {:ok, updated} = Registry.add_repo(reg, repo)
          updated
        end)

      %{registry: registry}
    end

    test "returns all repos", %{registry: registry} do
      repos = Registry.list_repos(registry)
      assert length(repos) == 3
    end

    test "filters by status", %{registry: registry} do
      repos = Registry.list_repos(registry, status: :active)
      assert length(repos) == 2
      assert Enum.all?(repos, &(&1.status == :active))
    end

    test "filters by type", %{registry: registry} do
      repos = Registry.list_repos(registry, type: :library)
      assert length(repos) == 2
    end

    test "filters by language", %{registry: registry} do
      repos = Registry.list_repos(registry, language: :elixir)
      assert length(repos) == 2
    end

    test "filters by tags", %{registry: registry} do
      repos = Registry.list_repos(registry, tags: ["core"])
      assert length(repos) == 1
      assert hd(repos).id == "lib-1"
    end

    test "sorts by name", %{registry: registry} do
      repos = Registry.list_repos(registry, sort: :name)
      ids = Enum.map(repos, & &1.id)
      assert ids == Enum.sort(ids)
    end
  end

  describe "add_relationship/2" do
    test "adds relationship to registry" do
      registry = Registry.new()
      {:ok, rel} = Relationship.new(%{from: "a", to: "b", type: :depends_on})

      assert {:ok, updated} = Registry.add_relationship(registry, rel)
      assert length(updated.relationships) == 1
    end

    test "replaces existing relationship with same from/to/type" do
      registry = Registry.new()

      {:ok, rel1} =
        Relationship.new(%{from: "a", to: "b", type: :depends_on, details: %{"v" => 1}})

      {:ok, rel2} =
        Relationship.new(%{from: "a", to: "b", type: :depends_on, details: %{"v" => 2}})

      {:ok, registry} = Registry.add_relationship(registry, rel1)
      {:ok, registry} = Registry.add_relationship(registry, rel2)

      assert length(registry.relationships) == 1
      assert hd(registry.relationships).details == %{"v" => 2}
    end
  end

  describe "get_relationships/2" do
    test "returns relationships for repo" do
      registry = Registry.new()
      {:ok, rel1} = Relationship.new(%{from: "a", to: "b", type: :depends_on})
      {:ok, rel2} = Relationship.new(%{from: "b", to: "c", type: :depends_on})
      {:ok, rel3} = Relationship.new(%{from: "d", to: "b", type: :related_to})

      {:ok, registry} = Registry.add_relationship(registry, rel1)
      {:ok, registry} = Registry.add_relationship(registry, rel2)
      {:ok, registry} = Registry.add_relationship(registry, rel3)

      rels = Registry.get_relationships(registry, "b")
      assert length(rels) == 3
    end

    test "returns empty list for repo with no relationships" do
      registry = Registry.new()

      rels = Registry.get_relationships(registry, "lonely")
      assert rels == []
    end
  end

  describe "search/3" do
    setup do
      registry = Registry.new()

      repos = [
        %{id: "auth-lib", name: "Authentication Library", purpose: "Handle user auth"},
        %{id: "api-gateway", name: "API Gateway", purpose: "Route requests"},
        %{id: "data-store", name: "Data Store", tags: ["database", "auth"]}
      ]

      registry =
        Enum.reduce(repos, registry, fn attrs, reg ->
          {:ok, repo} = Repo.new(attrs)
          {:ok, updated} = Registry.add_repo(reg, repo)
          updated
        end)

      %{registry: registry}
    end

    test "searches by id", %{registry: registry} do
      results = Registry.search(registry, "auth")
      assert length(results) == 2
    end

    test "searches by name", %{registry: registry} do
      results = Registry.search(registry, "gateway")
      assert length(results) == 1
    end

    test "searches by purpose", %{registry: registry} do
      results = Registry.search(registry, "user")
      assert length(results) == 1
    end

    test "searches by tags", %{registry: registry} do
      results = Registry.search(registry, "database")
      assert length(results) == 1
    end

    test "is case insensitive", %{registry: registry} do
      results = Registry.search(registry, "API")
      assert length(results) == 1
    end

    test "filters by fields", %{registry: registry} do
      results = Registry.search(registry, "auth", fields: [:id])
      assert length(results) == 1
      assert hd(results).id == "auth-lib"
    end
  end

  describe "stats/1" do
    test "returns statistics" do
      registry = Registry.new()

      repos = [
        %{id: "a", type: :library, status: :active, language: :elixir},
        %{id: "b", type: :library, status: :active, language: :elixir},
        %{id: "c", type: :application, status: :stale, language: :python}
      ]

      registry =
        Enum.reduce(repos, registry, fn attrs, reg ->
          {:ok, repo} = Repo.new(attrs)
          {:ok, updated} = Registry.add_repo(reg, repo)
          updated
        end)

      {:ok, rel} = Relationship.new(%{from: "a", to: "b"})
      {:ok, registry} = Registry.add_relationship(registry, rel)

      stats = Registry.stats(registry)

      assert stats.total == 3
      assert stats.by_status[:active] == 2
      assert stats.by_status[:stale] == 1
      assert stats.by_type[:library] == 2
      assert stats.by_language[:elixir] == 2
      assert stats.relationships == 1
    end
  end

  describe "to_data/1" do
    test "converts registry to serializable data" do
      registry = Registry.new()
      {:ok, repo} = Repo.new(%{id: "my-repo", type: :library})
      {:ok, registry} = Registry.add_repo(registry, repo)
      {:ok, rel} = Relationship.new(%{from: "a", to: "b"})
      {:ok, registry} = Registry.add_relationship(registry, rel)

      {repos_data, rels_data} = Registry.to_data(registry)

      assert length(repos_data) == 1
      assert hd(repos_data)["id"] == "my-repo"
      assert length(rels_data) == 1
    end
  end
end
