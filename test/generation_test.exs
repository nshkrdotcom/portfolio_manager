defmodule PortfolioManager.GenerationTest do
  use PortfolioManager.SupertesterCase, async: true

  alias PortfolioManager.Generation

  describe "new/2" do
    test "creates a new generation with query" do
      gen = Generation.new("What is this code doing?")

      assert gen.query == "What is this code doing?"
      assert is_binary(gen.id)
      assert String.length(gen.id) == 32
      assert gen.halted? == false
      assert gen.errors == []
      assert gen.query_embedding == nil
      assert gen.retrieval_results == nil
      assert gen.context == nil
      assert gen.context_sources == nil
      assert gen.prompt == nil
      assert gen.response == nil
      assert gen.evaluations == %{}
      assert gen.metadata == %{}
    end

    test "creates generation with options" do
      gen = Generation.new("query", metadata: %{user_id: "123"})

      assert gen.query == "query"
      assert gen.metadata == %{user_id: "123"}
    end
  end

  describe "with_embedding/2" do
    test "adds embedding to generation" do
      gen = Generation.new("query")
      embedding = [0.1, 0.2, 0.3]

      gen = Generation.with_embedding(gen, embedding)

      assert gen.query_embedding == embedding
    end
  end

  describe "with_retrieval/2" do
    test "adds retrieval results to generation" do
      gen = Generation.new("query")
      results = [%{content: "result 1"}, %{content: "result 2"}]

      gen = Generation.with_retrieval(gen, results)

      assert gen.retrieval_results == results
    end
  end

  describe "with_context/3" do
    test "adds context and sources to generation" do
      gen = Generation.new("query")
      context = "This is the assembled context"
      sources = ["file1.ex:10", "file2.ex:20"]

      gen = Generation.with_context(gen, context, sources)

      assert gen.context == context
      assert gen.context_sources == sources
    end
  end

  describe "with_prompt/2" do
    test "adds prompt to generation" do
      gen = Generation.new("query")
      prompt = "Given the context, answer the question"

      gen = Generation.with_prompt(gen, prompt)

      assert gen.prompt == prompt
    end
  end

  describe "with_response/2" do
    test "adds response to generation" do
      gen = Generation.new("query")
      response = "This is the LLM response"

      gen = Generation.with_response(gen, response)

      assert gen.response == response
    end
  end

  describe "with_evaluation/3" do
    test "adds evaluation result to generation" do
      gen = Generation.new("query")
      eval_result = %{score: 4, reasoning: "Good answer"}

      gen = Generation.with_evaluation(gen, :answer_relevance, eval_result)

      assert gen.evaluations.answer_relevance == eval_result
    end

    test "accumulates multiple evaluations" do
      gen = Generation.new("query")

      gen =
        gen
        |> Generation.with_evaluation(:context_relevance, %{score: 5})
        |> Generation.with_evaluation(:groundedness, %{score: 4})

      assert gen.evaluations.context_relevance == %{score: 5}
      assert gen.evaluations.groundedness == %{score: 4}
    end
  end

  describe "halt/2" do
    test "marks generation as halted with reason" do
      gen = Generation.new("query")

      gen = Generation.halt(gen, :no_results)

      assert gen.halted? == true
      assert :no_results in gen.errors
    end
  end

  describe "add_error/2" do
    test "adds error without halting" do
      gen = Generation.new("query")

      gen = Generation.add_error(gen, {:retrieval, :timeout})

      assert {:retrieval, :timeout} in gen.errors
      assert gen.halted? == false
    end

    test "accumulates multiple errors" do
      gen = Generation.new("query")

      gen =
        gen
        |> Generation.add_error(:error1)
        |> Generation.add_error(:error2)

      assert :error1 in gen.errors
      assert :error2 in gen.errors
    end
  end

  describe "success?/1" do
    test "returns true when not halted and has response" do
      gen =
        Generation.new("query")
        |> Generation.with_response("answer")

      assert Generation.success?(gen) == true
    end

    test "returns false when halted" do
      gen =
        Generation.new("query")
        |> Generation.with_response("answer")
        |> Generation.halt(:quality_check_failed)

      assert Generation.success?(gen) == false
    end

    test "returns false when no response" do
      gen = Generation.new("query")

      assert Generation.success?(gen) == false
    end
  end

  describe "pipeline composition" do
    test "supports full RAG pipeline workflow" do
      gen =
        Generation.new("What does this function do?", metadata: %{repo: "my_app"})
        |> Generation.with_embedding([0.1, 0.2, 0.3])
        |> Generation.with_retrieval([%{content: "def foo, do: :bar"}])
        |> Generation.with_context("def foo, do: :bar", ["lib/app.ex:10"])
        |> Generation.with_prompt("Given context, explain function")
        |> Generation.with_response("The function foo returns the atom :bar")
        |> Generation.with_evaluation(:groundedness, %{score: 5, reasoning: "Fully grounded"})

      assert gen.query == "What does this function do?"
      assert gen.metadata.repo == "my_app"
      assert gen.query_embedding == [0.1, 0.2, 0.3]
      assert length(gen.retrieval_results) == 1
      assert gen.context_sources == ["lib/app.ex:10"]
      assert gen.response =~ "foo"
      assert gen.evaluations.groundedness.score == 5
      assert Generation.success?(gen)
    end
  end
end
