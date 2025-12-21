defmodule PortfolioManager.Domain.ContextTest do
  use ExUnit.Case, async: true

  alias PortfolioManager.Domain.{Context, Repo}

  describe "new/1" do
    test "creates context from repo" do
      {:ok, repo} = Repo.new(%{id: "my-repo", name: "My Repo"})

      context = Context.new(repo)

      assert context.repo == repo
      assert context.notes == nil
      assert context.decisions == []
      assert context.todos == []
    end
  end

  describe "from_map/1" do
    test "creates context from map" do
      attrs = %{
        "id" => "my-repo",
        "name" => "My Repo",
        "type" => "library",
        "notes" => "Some notes",
        "todos" => ["Task 1", "Task 2"]
      }

      assert {:ok, context} = Context.from_map(attrs)
      assert context.repo.id == "my-repo"
      assert context.notes == "Some notes"
      assert context.todos == ["Task 1", "Task 2"]
    end

    test "parses decisions" do
      attrs = %{
        "id" => "my-repo",
        "decisions" => [
          %{
            "id" => "001",
            "title" => "Decision 1",
            "content" => "Content",
            "date" => "2025-01-01"
          }
        ]
      }

      assert {:ok, context} = Context.from_map(attrs)
      assert length(context.decisions) == 1
      assert hd(context.decisions).title == "Decision 1"
    end
  end

  describe "update/2" do
    test "updates context fields" do
      {:ok, repo} = Repo.new(%{id: "my-repo"})
      context = Context.new(repo)

      assert {:ok, updated} = Context.update(context, %{notes: "Updated notes"})
      assert updated.notes == "Updated notes"
    end

    test "updates repo fields" do
      {:ok, repo} = Repo.new(%{id: "my-repo", type: :unknown})
      context = Context.new(repo)

      assert {:ok, updated} = Context.update(context, %{type: :library})
      assert updated.repo.type == :library
    end

    test "updates nested repo map" do
      {:ok, repo} = Repo.new(%{id: "my-repo"})
      context = Context.new(repo)

      assert {:ok, updated} = Context.update(context, %{repo: %{status: :active}})
      assert updated.repo.status == :active
    end
  end

  describe "add_note/2" do
    test "adds note to empty notes" do
      {:ok, repo} = Repo.new(%{id: "my-repo"})
      context = Context.new(repo)

      updated = Context.add_note(context, "First note")

      assert updated.notes == "First note"
    end

    test "appends note to existing notes" do
      {:ok, repo} = Repo.new(%{id: "my-repo"})
      context = %{Context.new(repo) | notes: "Existing notes"}

      updated = Context.add_note(context, "New note")

      assert String.contains?(updated.notes, "Existing notes")
      assert String.contains?(updated.notes, "New note")
    end
  end

  describe "add_decision/3" do
    test "adds decision to context" do
      {:ok, repo} = Repo.new(%{id: "my-repo"})
      context = Context.new(repo)

      updated = Context.add_decision(context, "My Decision", "Decision content")

      assert length(updated.decisions) == 1
      decision = hd(updated.decisions)
      assert decision.id == "001"
      assert decision.title == "My Decision"
      assert decision.content == "Decision content"
      assert decision.date == Date.utc_today()
    end

    test "increments decision id" do
      {:ok, repo} = Repo.new(%{id: "my-repo"})
      context = Context.new(repo)

      context = Context.add_decision(context, "First", "Content")
      context = Context.add_decision(context, "Second", "Content")
      context = Context.add_decision(context, "Third", "Content")

      ids = Enum.map(context.decisions, & &1.id)
      assert ids == ["001", "002", "003"]
    end
  end

  describe "add_todo/2" do
    test "adds todo item" do
      {:ok, repo} = Repo.new(%{id: "my-repo"})
      context = Context.new(repo)

      updated = Context.add_todo(context, "New task")

      assert "New task" in updated.todos
    end

    test "appends to existing todos" do
      {:ok, repo} = Repo.new(%{id: "my-repo"})
      context = %{Context.new(repo) | todos: ["Existing task"]}

      updated = Context.add_todo(context, "New task")

      assert updated.todos == ["Existing task", "New task"]
    end
  end

  describe "remove_todo/2" do
    test "removes todo item" do
      {:ok, repo} = Repo.new(%{id: "my-repo"})
      context = %{Context.new(repo) | todos: ["Task 1", "Task 2", "Task 3"]}

      updated = Context.remove_todo(context, "Task 2")

      assert updated.todos == ["Task 1", "Task 3"]
    end

    test "handles non-existent todo" do
      {:ok, repo} = Repo.new(%{id: "my-repo"})
      context = %{Context.new(repo) | todos: ["Task 1"]}

      updated = Context.remove_todo(context, "Non-existent")

      assert updated.todos == ["Task 1"]
    end
  end

  describe "set_computed/3" do
    test "sets computed data" do
      {:ok, repo} = Repo.new(%{id: "my-repo"})
      context = Context.new(repo)

      updated = Context.set_computed(context, :commit_count, 42)

      assert updated.computed["commit_count"] == 42
    end

    test "overwrites existing computed data" do
      {:ok, repo} = Repo.new(%{id: "my-repo"})
      context = %{Context.new(repo) | computed: %{"key" => "old"}}

      updated = Context.set_computed(context, "key", "new")

      assert updated.computed["key"] == "new"
    end
  end

  describe "to_map/1" do
    test "converts context to map" do
      {:ok, repo} = Repo.new(%{id: "my-repo", type: :library})
      context = %{Context.new(repo) | notes: "Some notes", todos: ["Task 1"]}

      map = Context.to_map(context)

      assert map["id"] == "my-repo"
      assert map["type"] == "library"
      assert map["notes"] == "Some notes"
      assert map["todos"] == ["Task 1"]
    end

    test "excludes empty fields" do
      {:ok, repo} = Repo.new(%{id: "my-repo"})
      context = Context.new(repo)

      map = Context.to_map(context)

      refute Map.has_key?(map, "notes")
      refute Map.has_key?(map, "decisions")
      refute Map.has_key?(map, "todos")
    end
  end
end
