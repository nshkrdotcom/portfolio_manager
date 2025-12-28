defmodule PortfolioManager.CliTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO
  import Mox

  alias Mix.Tasks.Portfolio.{Ask, Graph, Index, Search}
  alias PortfolioManager.Mocks

  setup :verify_on_exit!

  setup do
    Mix.Task.clear()
    PortfolioCore.Registry.clear()

    PortfolioCore.Registry.register(:vector_store, {Mocks.VectorStore, []})
    PortfolioCore.Registry.register(:embedder, {Mocks.Embedder, []})
    PortfolioCore.Registry.register(:llm, {Mocks.LLM, []})
    PortfolioCore.Registry.register(:graph_store, {Mocks.GraphStore, []})

    :ok
  end

  describe "mix portfolio.ask" do
    test "prints answer" do
      Mocks.Embedder
      |> expect(:embed, fn _text, _opts ->
        {:ok, %{vector: List.duplicate(0.1, 3), token_count: 2, model: "test", dimensions: 3}}
      end)

      Mocks.VectorStore
      |> expect(:search, fn _index, _vector, _k, _opts ->
        {:ok, [%{id: "doc1", score: 0.9, metadata: %{}, content: "Elixir."}]}
      end)

      Mocks.LLM
      |> expect(:complete, fn _messages, _opts ->
        {:ok, %{content: "Elixir is functional.", usage: %{input_tokens: 1, output_tokens: 1}}}
      end)

      output =
        capture_io(fn ->
          Ask.run(["What", "is", "Elixir?"])
        end)

      assert output =~ "Elixir is functional."
    end
  end

  describe "mix portfolio.search" do
    test "prints search results" do
      Mocks.Embedder
      |> expect(:embed, fn _text, _opts ->
        {:ok, %{vector: List.duplicate(0.1, 3), token_count: 2, model: "test", dimensions: 3}}
      end)

      Mocks.VectorStore
      |> expect(:search, fn _index, _vector, _k, _opts ->
        {:ok, [%{id: "doc1", score: 0.9, metadata: %{}, content: "Search result."}]}
      end)

      output =
        capture_io(fn ->
          Search.run(["search", "term"])
        end)

      assert output =~ "Results: 1"
      assert output =~ "Search result."
    end
  end

  describe "mix portfolio.graph" do
    test "prints graph stats" do
      Mocks.GraphStore
      |> expect(:graph_stats, fn graph_id ->
        assert graph_id == "test_graph"
        {:ok, %{node_count: 2, edge_count: 1}}
      end)

      output =
        capture_io(fn ->
          Graph.run(["stats", "--graph", "test_graph"])
        end)

      assert output =~ "Nodes: 2"
      assert output =~ "Edges: 1"
    end
  end

  describe "mix portfolio.index" do
    test "indexes a repo path" do
      tmp_dir =
        Path.join(System.tmp_dir!(), "pm_index_test_#{System.unique_integer([:positive])}")

      File.mkdir_p!(tmp_dir)
      File.write!(Path.join(tmp_dir, "sample.md"), "# Hello\n")

      Mocks.VectorStore
      |> expect(:create_index, fn index_id, config ->
        assert index_id == "test_index"
        assert config.dimensions == 768
        :ok
      end)

      output =
        capture_io(fn ->
          Index.run([tmp_dir, "--index", "test_index", "--extensions", ".md"])
        end)

      assert output =~ "Queued 1 files"
    end
  end
end
