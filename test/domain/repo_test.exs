defmodule PortfolioManager.Domain.RepoTest do
  use ExUnit.Case, async: true

  alias PortfolioManager.Domain.Repo

  describe "new/1" do
    test "creates a repo with valid attributes" do
      attrs = %{
        id: "my-repo",
        name: "My Repo",
        path: "/path/to/repo",
        type: :library,
        status: :active,
        language: :elixir
      }

      assert {:ok, repo} = Repo.new(attrs)
      assert repo.id == "my-repo"
      assert repo.name == "My Repo"
      assert repo.type == :library
      assert repo.status == :active
      assert repo.language == :elixir
    end

    test "creates a repo with string keys" do
      attrs = %{
        "id" => "my-repo",
        "name" => "My Repo",
        "type" => "library",
        "status" => "active"
      }

      assert {:ok, repo} = Repo.new(attrs)
      assert repo.id == "my-repo"
      assert repo.type == :library
    end

    test "defaults type and status to :unknown" do
      attrs = %{id: "my-repo"}

      assert {:ok, repo} = Repo.new(attrs)
      assert repo.type == :unknown
      assert repo.status == :unknown
    end

    test "fails with missing id" do
      attrs = %{name: "My Repo"}

      assert {:error, :id_required} = Repo.new(attrs)
    end

    test "fails with empty id" do
      attrs = %{id: "", name: "My Repo"}

      assert {:error, :id_required} = Repo.new(attrs)
    end

    test "sets timestamps on creation" do
      attrs = %{id: "my-repo"}

      assert {:ok, repo} = Repo.new(attrs)
      assert %DateTime{} = repo.created_at
      assert %DateTime{} = repo.updated_at
    end

    test "normalizes port info" do
      attrs = %{
        id: "my-port",
        type: :port,
        port: %{
          "upstream_url" => "https://github.com/user/repo",
          "coverage" => "partial"
        }
      }

      assert {:ok, repo} = Repo.new(attrs)
      assert repo.port["upstream_url"] == "https://github.com/user/repo"
    end
  end

  describe "new!/1" do
    test "returns repo on success" do
      attrs = %{id: "my-repo"}
      repo = Repo.new!(attrs)
      assert repo.id == "my-repo"
    end

    test "raises on failure" do
      assert_raise ArgumentError, fn ->
        Repo.new!(%{name: "no id"})
      end
    end
  end

  describe "update/2" do
    test "updates fields" do
      {:ok, repo} = Repo.new(%{id: "my-repo", type: :unknown})

      assert {:ok, updated} = Repo.update(repo, %{type: :library, purpose: "Test library"})
      assert updated.type == :library
      assert updated.purpose == "Test library"
    end

    test "updates updated_at timestamp" do
      {:ok, repo} = Repo.new(%{id: "my-repo"})
      original_updated_at = repo.updated_at

      # Small delay to ensure different timestamp
      Process.sleep(1)

      assert {:ok, updated} = Repo.update(repo, %{name: "New Name"})
      assert DateTime.compare(updated.updated_at, original_updated_at) == :gt
    end

    test "handles string keys" do
      {:ok, repo} = Repo.new(%{id: "my-repo"})

      assert {:ok, updated} = Repo.update(repo, %{"type" => "library"})
      assert updated.type == :library
    end
  end

  describe "to_map/1" do
    test "converts repo to map with string keys" do
      {:ok, repo} =
        Repo.new(%{
          id: "my-repo",
          name: "My Repo",
          type: :library,
          status: :active,
          tags: ["tag1", "tag2"]
        })

      map = Repo.to_map(repo)

      assert map["id"] == "my-repo"
      assert map["type"] == "library"
      assert map["status"] == "active"
      assert map["tags"] == ["tag1", "tag2"]
    end

    test "excludes nil values" do
      {:ok, repo} = Repo.new(%{id: "my-repo"})

      map = Repo.to_map(repo)

      refute Map.has_key?(map, "path")
      refute Map.has_key?(map, "purpose")
    end
  end

  describe "generate_id/1" do
    test "generates id from path" do
      assert Repo.generate_id("/path/to/my-repo") == "my-repo"
    end

    test "handles spaces and special characters" do
      assert Repo.generate_id("/path/to/My Repo!") == "my-repo"
    end

    test "handles uppercase" do
      assert Repo.generate_id("MyProject") == "myproject"
    end
  end

  describe "validate/1" do
    test "validates required fields" do
      repo = %Repo{id: nil}
      assert {:error, :id_required} = Repo.validate(repo)
    end

    test "validates type" do
      repo = %Repo{id: "test", type: :invalid, status: :active}
      assert {:error, {:invalid_type, :invalid}} = Repo.validate(repo)
    end

    test "validates status" do
      repo = %Repo{id: "test", type: :library, status: :invalid}
      assert {:error, {:invalid_status, :invalid}} = Repo.validate(repo)
    end

    test "validates priority" do
      repo = %Repo{id: "test", type: :library, status: :active, priority: :invalid}
      assert {:error, {:invalid_priority, :invalid}} = Repo.validate(repo)
    end

    test "passes with valid repo" do
      repo = %Repo{id: "test", type: :library, status: :active}
      assert {:ok, ^repo} = Repo.validate(repo)
    end
  end
end
