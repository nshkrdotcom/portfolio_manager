defmodule PortfolioManager.EvaluationTest do
  use PortfolioManager.SupertesterCase, async: false

  import Mox

  alias PortfolioManager.Evaluation
  alias PortfolioManager.Generation
  alias PortfolioManager.Router

  setup :verify_on_exit!

  setup do
    # Stop any existing router
    case Process.whereis(Router) do
      nil -> :ok
      pid -> safe_stop(pid)
    end

    PortfolioCore.Registry.register(:llm, PortfolioManager.Mocks.LLM, model: "test")

    # Start router with mock LLM
    {:ok, router_pid} =
      Router.start_link(
        strategy: :fallback,
        providers: [
          %{
            name: :test_llm,
            module: PortfolioManager.Mocks.LLM,
            config: %{},
            capabilities: [:generation, :reasoning],
            priority: 1
          }
        ],
        health_check_interval: 0
      )

    on_exit(fn ->
      if Process.alive?(router_pid), do: safe_stop(router_pid)
      PortfolioCore.Registry.clear()
    end)

    :ok
  end

  defp sample_generation do
    Generation.new("What does this function do?")
    |> Generation.with_context(
      "def hello, do: IO.puts(\"Hello, world!\")",
      ["lib/greeter.ex:10"]
    )
    |> Generation.with_response("This function prints 'Hello, world!' to the console.")
  end

  describe "evaluate_context_relevance/2" do
    test "returns score and reasoning for relevant context" do
      PortfolioManager.Mocks.LLM
      |> expect(:complete, fn _messages, _opts ->
        {:ok, %{content: ~s({"score": 5, "reasoning": "Context directly answers the question"})}}
      end)

      gen = sample_generation()

      assert {:ok, result} = Evaluation.evaluate_context_relevance(gen)

      assert result.score == 5
      assert is_binary(result.reasoning)
    end

    test "handles scores in valid range" do
      for score <- [1, 2, 3, 4, 5] do
        PortfolioManager.Mocks.LLM
        |> expect(:complete, fn _messages, _opts ->
          {:ok, %{content: ~s({"score": #{score}, "reasoning": "Test"})}}
        end)

        gen = sample_generation()
        {:ok, result} = Evaluation.evaluate_context_relevance(gen)

        assert result.score == score
      end
    end

    test "returns error when LLM fails" do
      PortfolioManager.Mocks.LLM
      |> expect(:complete, fn _messages, _opts ->
        {:error, :rate_limited}
      end)

      gen = sample_generation()

      assert {:error, :rate_limited} = Evaluation.evaluate_context_relevance(gen)
    end
  end

  describe "evaluate_groundedness/2" do
    test "returns score and reasoning for grounded response" do
      PortfolioManager.Mocks.LLM
      |> expect(:complete, fn _messages, _opts ->
        {:ok, %{content: ~s({"score": 5, "reasoning": "All claims are supported by context"})}}
      end)

      gen = sample_generation()

      assert {:ok, result} = Evaluation.evaluate_groundedness(gen)

      assert result.score == 5
      assert is_binary(result.reasoning)
    end

    test "returns low score for ungrounded response" do
      PortfolioManager.Mocks.LLM
      |> expect(:complete, fn _messages, _opts ->
        {:ok, %{content: ~s({"score": 2, "reasoning": "Response contains unsupported claims"})}}
      end)

      gen = sample_generation()

      {:ok, result} = Evaluation.evaluate_groundedness(gen)

      assert result.score == 2
    end
  end

  describe "evaluate_answer_relevance/2" do
    test "returns score and reasoning for relevant answer" do
      PortfolioManager.Mocks.LLM
      |> expect(:complete, fn _messages, _opts ->
        {:ok, %{content: ~s({"score": 4, "reasoning": "Answer addresses the question well"})}}
      end)

      gen = sample_generation()

      assert {:ok, result} = Evaluation.evaluate_answer_relevance(gen)

      assert result.score == 4
      assert is_binary(result.reasoning)
    end
  end

  describe "evaluate_rag_triad/2" do
    test "evaluates all three dimensions" do
      # Expect three LLM calls, one for each dimension
      PortfolioManager.Mocks.LLM
      |> expect(:complete, fn _messages, _opts ->
        {:ok, %{content: ~s({"score": 5, "reasoning": "Context is very relevant"})}}
      end)
      |> expect(:complete, fn _messages, _opts ->
        {:ok, %{content: ~s({"score": 4, "reasoning": "Well grounded response"})}}
      end)
      |> expect(:complete, fn _messages, _opts ->
        {:ok, %{content: ~s({"score": 4, "reasoning": "Answer addresses query"})}}
      end)

      gen = sample_generation()

      assert {:ok, result} = Evaluation.evaluate_rag_triad(gen)

      assert result.context_relevance.score == 5
      assert result.groundedness.score == 4
      assert result.answer_relevance.score == 4
      assert is_float(result.overall)
    end

    test "calculates overall score as average" do
      PortfolioManager.Mocks.LLM
      |> expect(:complete, fn _messages, _opts ->
        {:ok, %{content: ~s({"score": 3, "reasoning": "Test"})}}
      end)
      |> expect(:complete, fn _messages, _opts ->
        {:ok, %{content: ~s({"score": 3, "reasoning": "Test"})}}
      end)
      |> expect(:complete, fn _messages, _opts ->
        {:ok, %{content: ~s({"score": 3, "reasoning": "Test"})}}
      end)

      gen = sample_generation()
      {:ok, result} = Evaluation.evaluate_rag_triad(gen)

      assert result.overall == 3.0
    end

    test "returns error if any evaluation fails" do
      PortfolioManager.Mocks.LLM
      |> expect(:complete, fn _messages, _opts ->
        {:ok, %{content: ~s({"score": 5, "reasoning": "Test"})}}
      end)
      |> expect(:complete, fn _messages, _opts ->
        {:error, :timeout}
      end)

      gen = sample_generation()

      assert {:error, _} = Evaluation.evaluate_rag_triad(gen)
    end
  end

  describe "detect_hallucination/2" do
    test "detects no hallucination in grounded response" do
      PortfolioManager.Mocks.LLM
      |> expect(:complete, fn _messages, _opts ->
        {:ok,
         %{
           content:
             ~s({"hallucinating": false, "evidence": "All claims are supported by context"})
         }}
      end)

      gen = sample_generation()

      assert {:ok, result} = Evaluation.detect_hallucination(gen)

      assert result.hallucinating == false
      assert is_binary(result.evidence)
    end

    test "detects hallucination in ungrounded response" do
      PortfolioManager.Mocks.LLM
      |> expect(:complete, fn _messages, _opts ->
        {:ok,
         %{
           content:
             ~s({"hallucinating": true, "evidence": "Response claims the function returns a value, but it doesn't"})
         }}
      end)

      gen = sample_generation()

      {:ok, result} = Evaluation.detect_hallucination(gen)

      assert result.hallucinating == true
      assert String.contains?(result.evidence, "claims")
    end

    test "returns error when LLM fails" do
      PortfolioManager.Mocks.LLM
      |> expect(:complete, fn _messages, _opts ->
        {:error, :rate_limited}
      end)

      gen = sample_generation()

      assert {:error, :rate_limited} = Evaluation.detect_hallucination(gen)
    end
  end

  describe "telemetry events" do
    test "emits telemetry for rag_triad evaluation" do
      :telemetry.attach(
        "triad-test",
        [:portfolio_manager, :evaluation, :rag_triad],
        fn _event, measurements, metadata, _config ->
          send(self(), {:telemetry, measurements, metadata})
        end,
        nil
      )

      on_exit(fn -> :telemetry.detach("triad-test") end)

      PortfolioManager.Mocks.LLM
      |> expect(:complete, 3, fn _messages, _opts ->
        {:ok, %{content: ~s({"score": 4, "reasoning": "Test"})}}
      end)

      gen = sample_generation()
      {:ok, _} = Evaluation.evaluate_rag_triad(gen)

      assert_receive {:telemetry, _measurements, metadata}
      assert metadata.generation_id == gen.id
    end

    test "emits telemetry for hallucination detection" do
      :telemetry.attach(
        "hallucination-test",
        [:portfolio_manager, :evaluation, :hallucination],
        fn _event, measurements, metadata, _config ->
          send(self(), {:telemetry, measurements, metadata})
        end,
        nil
      )

      on_exit(fn -> :telemetry.detach("hallucination-test") end)

      PortfolioManager.Mocks.LLM
      |> expect(:complete, fn _messages, _opts ->
        {:ok, %{content: ~s({"hallucinating": false, "evidence": "Grounded"})}}
      end)

      gen = sample_generation()
      {:ok, _} = Evaluation.detect_hallucination(gen)

      assert_receive {:telemetry, _measurements, metadata}
      assert metadata.generation_id == gen.id
    end
  end

  describe "input validation" do
    test "works with map input matching generation shape" do
      PortfolioManager.Mocks.LLM
      |> expect(:complete, fn _messages, _opts ->
        {:ok, %{content: ~s({"score": 4, "reasoning": "Valid input"})}}
      end)

      gen = %{
        id: "test-id",
        query: "What is this?",
        context: "def foo, do: :bar",
        context_sources: ["file.ex:1"],
        response: "It returns :bar"
      }

      assert {:ok, result} = Evaluation.evaluate_context_relevance(gen)
      assert result.score == 4
    end
  end
end
