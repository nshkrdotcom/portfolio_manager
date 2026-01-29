defmodule PortfolioManager.RAGStreamingTest do
  use PortfolioManager.SupertesterCase, async: false

  import ExUnit.CaptureLog

  import Mox

  alias PortfolioManager.Mocks
  alias PortfolioManager.RAG
  alias PortfolioManager.Router

  setup :verify_on_exit!

  setup do
    # Stop any existing router started by the application
    case Process.whereis(Router) do
      nil -> :ok
      pid -> safe_stop(pid)
    end

    # Register mock adapters
    PortfolioCore.Registry.register(:vector_store, Mocks.VectorStore, [])
    PortfolioCore.Registry.register(:embedder, Mocks.Embedder, [])
    PortfolioCore.Registry.register(:llm, Mocks.LLM, [])

    # Start the router with a mock LLM provider
    {:ok, router_pid} =
      Router.start_link(
        strategy: :fallback,
        providers: [
          %{
            name: :streaming_llm,
            module: Mocks.LLM,
            config: %{},
            capabilities: [:generation, :reasoning],
            priority: 1
          }
        ],
        health_check_interval: 0
      )

    on_exit(fn ->
      PortfolioCore.Registry.clear()
      if Process.alive?(router_pid), do: safe_stop(router_pid)
    end)

    :ok
  end

  describe "stream_query/3" do
    test "streams response chunks through callback" do
      # Mock embedding
      Mocks.Embedder
      |> expect(:embed, fn _text, _opts ->
        {:ok, %{vector: List.duplicate(0.1, 768), token_count: 2, model: "test", dimensions: 768}}
      end)

      # Mock vector search and fulltext search (hybrid strategy)
      Mocks.VectorStore
      |> expect(:search, fn _index, _vector, _k, _opts ->
        {:ok,
         [
           %{id: "doc1", score: 0.9, content: "Context document", metadata: %{}, vector: nil}
         ]}
      end)
      |> expect(:fulltext_search, fn _index, _query, _k, _opts ->
        {:ok, []}
      end)

      # Mock streaming LLM response - stream/2 returns enumerable
      Mocks.LLM
      |> expect(:stream, fn _messages, _opts ->
        {:ok, [%{delta: "Hello"}, %{delta: " "}, %{delta: "World"}]}
      end)

      received = Agent.start_link(fn -> [] end) |> elem(1)

      callback = fn chunk ->
        Agent.update(received, &[chunk | &1])
      end

      assert :ok = RAG.stream_query("test question", callback)

      result = Agent.get(received, & &1) |> Enum.reverse()
      assert result == ["Hello", " ", "World"]
    end

    test "uses specified strategy for retrieval" do
      Mocks.Embedder
      |> expect(:embed, fn _text, _opts ->
        {:ok, %{vector: List.duplicate(0.1, 768), token_count: 2, model: "test", dimensions: 768}}
      end)

      # Hybrid strategy calls vector search and fulltext search
      Mocks.VectorStore
      |> expect(:search, fn _index, _vector, _k, _opts ->
        {:ok, [%{id: "doc1", score: 0.9, content: "Context", metadata: %{}, vector: nil}]}
      end)
      |> expect(:fulltext_search, fn _index, _query, _k, _opts ->
        {:ok, []}
      end)

      Mocks.LLM
      |> expect(:stream, fn _messages, _opts ->
        # stream/2 returns {:ok, enumerable}
        {:ok, [%{delta: "Streamed response"}]}
      end)

      assert :ok = RAG.stream_query("test", fn _ -> :ok end, strategy: :hybrid, top_k: 3)
    end

    test "returns error when retrieval fails" do
      Mocks.Embedder
      |> expect(:embed, fn _text, _opts ->
        {:error, :embedding_failed}
      end)

      capture_log(fn ->
        assert {:error, _} = RAG.stream_query("test", fn _ -> :ok end)
      end)
    end
  end

  describe "stream_search/3" do
    test "streams search results through callback" do
      Mocks.Embedder
      |> expect(:embed, fn _text, _opts ->
        {:ok, %{vector: List.duplicate(0.1, 768), token_count: 2, model: "test", dimensions: 768}}
      end)

      Mocks.VectorStore
      |> expect(:search, fn _index, _vector, _k, _opts ->
        {:ok,
         [
           %{id: "doc1", score: 0.9, content: "First", metadata: %{}, vector: nil},
           %{id: "doc2", score: 0.8, content: "Second", metadata: %{}, vector: nil},
           %{id: "doc3", score: 0.7, content: "Third", metadata: %{}, vector: nil}
         ]}
      end)

      received = Agent.start_link(fn -> [] end) |> elem(1)

      callback = fn result ->
        Agent.update(received, &[result | &1])
      end

      assert :ok = RAG.stream_search("test query", callback, limit: 3)

      results = Agent.get(received, & &1)
      assert length(results) == 3
    end

    test "respects limit option" do
      Mocks.Embedder
      |> expect(:embed, fn _text, _opts ->
        {:ok, %{vector: List.duplicate(0.1, 768), token_count: 2, model: "test", dimensions: 768}}
      end)

      Mocks.VectorStore
      |> expect(:search, fn _index, _vector, _k, _opts ->
        {:ok,
         [
           %{id: "doc1", score: 0.9, content: "First", metadata: %{}, vector: nil},
           %{id: "doc2", score: 0.8, content: "Second", metadata: %{}, vector: nil},
           %{id: "doc3", score: 0.7, content: "Third", metadata: %{}, vector: nil}
         ]}
      end)

      received = Agent.start_link(fn -> [] end) |> elem(1)

      callback = fn result ->
        Agent.update(received, &[result | &1])
      end

      assert :ok = RAG.stream_search("test query", callback, limit: 2)

      results = Agent.get(received, & &1)
      assert length(results) == 2
    end
  end
end
