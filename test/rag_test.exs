defmodule PortfolioManager.RAGTest do
  use ExUnit.Case, async: false

  import Mox

  alias PortfolioManager.Mocks
  alias PortfolioManager.RAG

  setup :verify_on_exit!

  setup do
    # Register mock adapters
    PortfolioCore.Registry.register(:vector_store, {Mocks.VectorStore, []})
    PortfolioCore.Registry.register(:embedder, {Mocks.Embedder, []})
    PortfolioCore.Registry.register(:llm, {Mocks.LLM, []})

    on_exit(fn ->
      PortfolioCore.Registry.clear()
    end)

    :ok
  end

  describe "query/2" do
    test "returns results using hybrid strategy" do
      Mocks.Embedder
      |> expect(:embed, fn text, _opts ->
        assert text == "test query"

        {:ok,
         %{vector: List.duplicate(0.1, 1536), token_count: 2, model: "test", dimensions: 1536}}
      end)

      Mocks.VectorStore
      |> expect(:search, fn _index, _vector, k, _opts ->
        assert k == 20

        {:ok,
         [
           %{id: "doc1", score: 0.95, metadata: %{content: "result 1"}, vector: nil}
         ]}
      end)

      assert {:ok, result} = RAG.query("test query", strategy: :hybrid)
      assert length(result.items) == 1
      assert result.strategy == :hybrid
    end
  end

  describe "ask/2" do
    test "generates answer from retrieved context" do
      Mocks.Embedder
      |> expect(:embed, fn _text, _opts ->
        {:ok,
         %{vector: List.duplicate(0.1, 1536), token_count: 2, model: "test", dimensions: 1536}}
      end)

      Mocks.VectorStore
      |> expect(:search, fn _index, _vector, _k, _opts ->
        {:ok,
         [
           %{
             id: "doc1",
             score: 0.95,
             metadata: %{},
             vector: nil,
             content: "Elixir is a functional language."
           }
         ]}
      end)

      Mocks.LLM
      |> expect(:complete, fn messages, _opts ->
        assert length(messages) == 2

        {:ok,
         %{
           content: "Elixir is a functional programming language.",
           usage: %{input_tokens: 10, output_tokens: 8},
           finish_reason: :stop
         }}
      end)

      assert {:ok, answer} = RAG.ask("What is Elixir?")
      assert String.contains?(answer, "Elixir")
    end
  end
end
