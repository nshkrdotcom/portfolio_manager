defmodule PortfolioManager.Adapters.MarkdownStorageTest do
  @moduledoc """
  Tests for markdown file persistence in YAML storage adapter.

  Verifies that:
  - Notes persist to repos/{id}/notes.md
  - Decisions persist to repos/{id}/decisions/{NNN}-{slug}.md
  - Loading context reads markdown files back correctly
  """

  use ExUnit.Case, async: true

  alias PortfolioManager.Adapters.YAMLStorage
  alias PortfolioManager.Domain.{Context, Repo}

  setup do
    # Create a temporary directory for each test
    tmp_dir = Path.join(System.tmp_dir!(), "portfolio_md_test_#{:rand.uniform(1_000_000)}")
    File.rm_rf!(tmp_dir)
    :ok = YAMLStorage.create(tmp_dir)
    {:ok, state} = YAMLStorage.init(tmp_dir)

    on_exit(fn -> File.rm_rf!(tmp_dir) end)

    {:ok, state: state, tmp_dir: tmp_dir}
  end

  describe "notes persistence" do
    test "saves notes to notes.md file", %{state: state, tmp_dir: tmp_dir} do
      {:ok, repo} = Repo.new(%{id: "test-repo", path: "/tmp/test"})
      context = Context.new(repo)
      context = Context.add_note(context, "This is a test note")

      :ok = YAMLStorage.save_context(state, context)

      notes_path = Path.join([tmp_dir, "repos", "test-repo", "notes.md"])
      assert File.exists?(notes_path)

      content = File.read!(notes_path)
      assert String.contains?(content, "This is a test note")
    end

    test "loads notes from notes.md file", %{state: state} do
      {:ok, repo} = Repo.new(%{id: "test-repo", path: "/tmp/test"})
      context = Context.new(repo)
      context = Context.add_note(context, "Persisted note content")

      :ok = YAMLStorage.save_context(state, context)
      {:ok, loaded} = YAMLStorage.load_context(state, "test-repo")

      assert String.contains?(loaded.notes, "Persisted note content")
    end

    test "appends notes correctly", %{state: state} do
      {:ok, repo} = Repo.new(%{id: "test-repo", path: "/tmp/test"})
      context = Context.new(repo)
      context = Context.add_note(context, "First note")
      context = Context.add_note(context, "Second note")

      :ok = YAMLStorage.save_context(state, context)
      {:ok, loaded} = YAMLStorage.load_context(state, "test-repo")

      assert String.contains?(loaded.notes, "First note")
      assert String.contains?(loaded.notes, "Second note")
    end

    test "handles empty notes gracefully", %{state: state, tmp_dir: tmp_dir} do
      {:ok, repo} = Repo.new(%{id: "test-repo", path: "/tmp/test"})
      context = Context.new(repo)

      :ok = YAMLStorage.save_context(state, context)

      notes_path = Path.join([tmp_dir, "repos", "test-repo", "notes.md"])
      # Empty notes should not create a file
      refute File.exists?(notes_path)
    end
  end

  describe "decisions persistence" do
    test "saves decisions to individual markdown files", %{state: state, tmp_dir: tmp_dir} do
      {:ok, repo} = Repo.new(%{id: "test-repo", path: "/tmp/test"})
      context = Context.new(repo)

      context =
        Context.add_decision(context, "Use GenServer", "We chose GenServer for state management.")

      :ok = YAMLStorage.save_context(state, context)

      decisions_dir = Path.join([tmp_dir, "repos", "test-repo", "decisions"])
      assert File.dir?(decisions_dir)

      # Should create a file like 001-use-genserver.md
      files = File.ls!(decisions_dir)
      assert length(files) == 1
      [filename] = files
      assert String.starts_with?(filename, "001-")
      assert String.ends_with?(filename, ".md")
    end

    test "creates decision files with correct ADR format", %{state: state, tmp_dir: tmp_dir} do
      {:ok, repo} = Repo.new(%{id: "test-repo", path: "/tmp/test"})
      context = Context.new(repo)

      context =
        Context.add_decision(context, "Use GenServer", "We chose GenServer for state management.")

      :ok = YAMLStorage.save_context(state, context)

      decisions_dir = Path.join([tmp_dir, "repos", "test-repo", "decisions"])
      [filename] = File.ls!(decisions_dir)
      content = File.read!(Path.join(decisions_dir, filename))

      # Verify ADR format
      assert String.contains?(content, "# ADR-001: Use GenServer")
      assert String.contains?(content, "**Date**:")
      assert String.contains?(content, "We chose GenServer for state management.")
    end

    test "loads decisions from markdown files", %{state: state} do
      {:ok, repo} = Repo.new(%{id: "test-repo", path: "/tmp/test"})
      context = Context.new(repo)
      context = Context.add_decision(context, "Use GenServer", "For state management")
      context = Context.add_decision(context, "Use ETS", "For caching")

      :ok = YAMLStorage.save_context(state, context)
      {:ok, loaded} = YAMLStorage.load_context(state, "test-repo")

      assert length(loaded.decisions) == 2
      titles = Enum.map(loaded.decisions, & &1.title)
      assert "Use GenServer" in titles
      assert "Use ETS" in titles
    end

    test "decision filename uses slugified title", %{state: state, tmp_dir: tmp_dir} do
      {:ok, repo} = Repo.new(%{id: "test-repo", path: "/tmp/test"})
      context = Context.new(repo)
      context = Context.add_decision(context, "Use Phoenix Framework", "For web development")

      :ok = YAMLStorage.save_context(state, context)

      decisions_dir = Path.join([tmp_dir, "repos", "test-repo", "decisions"])
      [filename] = File.ls!(decisions_dir)
      assert filename == "001-use-phoenix-framework.md"
    end

    test "handles multiple decisions with proper numbering", %{state: state, tmp_dir: tmp_dir} do
      {:ok, repo} = Repo.new(%{id: "test-repo", path: "/tmp/test"})
      context = Context.new(repo)
      context = Context.add_decision(context, "First Decision", "Content 1")
      context = Context.add_decision(context, "Second Decision", "Content 2")
      context = Context.add_decision(context, "Third Decision", "Content 3")

      :ok = YAMLStorage.save_context(state, context)

      decisions_dir = Path.join([tmp_dir, "repos", "test-repo", "decisions"])
      files = File.ls!(decisions_dir) |> Enum.sort()

      assert length(files) == 3
      assert Enum.at(files, 0) =~ ~r/^001-/
      assert Enum.at(files, 1) =~ ~r/^002-/
      assert Enum.at(files, 2) =~ ~r/^003-/
    end

    test "handles empty decisions list", %{state: state, tmp_dir: tmp_dir} do
      {:ok, repo} = Repo.new(%{id: "test-repo", path: "/tmp/test"})
      context = Context.new(repo)

      :ok = YAMLStorage.save_context(state, context)

      decisions_dir = Path.join([tmp_dir, "repos", "test-repo", "decisions"])
      # Directory should not be created if no decisions
      refute File.dir?(decisions_dir)
    end

    test "preserves decision dates when loading", %{state: state} do
      {:ok, repo} = Repo.new(%{id: "test-repo", path: "/tmp/test"})
      context = Context.new(repo)
      context = Context.add_decision(context, "Test Decision", "Content")

      :ok = YAMLStorage.save_context(state, context)
      {:ok, loaded} = YAMLStorage.load_context(state, "test-repo")

      [decision] = loaded.decisions
      assert %Date{} = decision.date
    end
  end

  describe "combined notes and decisions" do
    test "saves and loads both notes and decisions together", %{state: state} do
      {:ok, repo} = Repo.new(%{id: "test-repo", path: "/tmp/test"})
      context = Context.new(repo)
      context = Context.add_note(context, "Some notes here")
      context = Context.add_decision(context, "Important Decision", "The reasoning")

      :ok = YAMLStorage.save_context(state, context)
      {:ok, loaded} = YAMLStorage.load_context(state, "test-repo")

      assert String.contains?(loaded.notes, "Some notes here")
      assert length(loaded.decisions) == 1
      assert hd(loaded.decisions).title == "Important Decision"
    end

    test "context.yml does not contain notes or decision content", %{
      state: state,
      tmp_dir: tmp_dir
    } do
      {:ok, repo} = Repo.new(%{id: "test-repo", path: "/tmp/test"})
      context = Context.new(repo)
      context = Context.add_note(context, "Secret notes")
      context = Context.add_decision(context, "Secret Decision", "Secret reasoning")

      :ok = YAMLStorage.save_context(state, context)

      context_yml = Path.join([tmp_dir, "repos", "test-repo", "context.yml"])
      content = File.read!(context_yml)

      # Notes and full decision content should NOT be in context.yml
      refute String.contains?(content, "Secret notes")
      refute String.contains?(content, "Secret reasoning")
    end
  end

  describe "edge cases" do
    test "handles special characters in decision titles", %{state: state, tmp_dir: tmp_dir} do
      {:ok, repo} = Repo.new(%{id: "test-repo", path: "/tmp/test"})
      context = Context.new(repo)
      context = Context.add_decision(context, "Use API: REST vs GraphQL?", "Comparison content")

      :ok = YAMLStorage.save_context(state, context)

      decisions_dir = Path.join([tmp_dir, "repos", "test-repo", "decisions"])
      [filename] = File.ls!(decisions_dir)
      # Special chars should be removed or replaced
      assert filename == "001-use-api-rest-vs-graphql.md"
    end

    test "handles unicode in notes", %{state: state} do
      {:ok, repo} = Repo.new(%{id: "test-repo", path: "/tmp/test"})
      context = Context.new(repo)
      context = Context.add_note(context, "Unicode test: émojis 🎉 and symbols ∑∆")

      :ok = YAMLStorage.save_context(state, context)
      {:ok, loaded} = YAMLStorage.load_context(state, "test-repo")

      assert String.contains?(loaded.notes, "émojis 🎉")
    end

    test "handles very long decision titles", %{state: state, tmp_dir: tmp_dir} do
      {:ok, repo} = Repo.new(%{id: "test-repo", path: "/tmp/test"})
      context = Context.new(repo)
      long_title = String.duplicate("Very Long Title ", 20)
      context = Context.add_decision(context, long_title, "Content")

      :ok = YAMLStorage.save_context(state, context)

      decisions_dir = Path.join([tmp_dir, "repos", "test-repo", "decisions"])
      [filename] = File.ls!(decisions_dir)
      # Filename should be truncated to reasonable length
      assert String.length(filename) <= 100
    end
  end
end
