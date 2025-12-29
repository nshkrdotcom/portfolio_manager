defmodule PortfolioManager.Evaluation do
  @moduledoc """
  RAG evaluation using the RAG triad: context relevance, groundedness, answer relevance.

  Provides quality assessment for RAG responses with scores 1-5 and reasoning.

  ## RAG Triad

  The RAG triad evaluates three key dimensions:

    * **Context Relevance** - Is the retrieved context relevant to the query?
    * **Groundedness** - Is the response supported by the provided context?
    * **Answer Relevance** - Does the response actually address the query?

  ## Scores

  Each dimension is scored 1-5:

    * 1 = Very poor
    * 2 = Poor
    * 3 = Acceptable
    * 4 = Good
    * 5 = Excellent

  ## Usage

      generation =
        Generation.new("What does this do?")
        |> Generation.with_context("def foo, do: :bar", ["file.ex:1"])
        |> Generation.with_response("It returns :bar")

      {:ok, triad} = Evaluation.evaluate_rag_triad(generation)
      # => %{context_relevance: %{score: 5, ...}, groundedness: %{...}, ...}

      {:ok, result} = Evaluation.detect_hallucination(generation)
      # => %{hallucinating: false, evidence: "..."}

  ## Telemetry

  Emits telemetry events:

    * `[:portfolio_manager, :evaluation, :rag_triad]`
    * `[:portfolio_manager, :evaluation, :hallucination]`
  """

  @behaviour PortfolioCore.Ports.Evaluation

  alias PortfolioManager.Router

  @type generation :: %{
          query: String.t(),
          context: String.t(),
          response: String.t(),
          context_sources: [String.t()]
        }

  @type triad_score :: %{
          score: 1..5,
          reasoning: String.t()
        }

  @type triad_result :: %{
          context_relevance: triad_score(),
          groundedness: triad_score(),
          answer_relevance: triad_score(),
          overall: float()
        }

  @type hallucination_result :: %{
          hallucinating: boolean(),
          evidence: String.t()
        }

  @doc """
  Evaluate a RAG generation using the RAG Triad framework.

  Evaluates context relevance, groundedness, and answer relevance,
  returning scores and reasoning for each dimension plus an overall score.
  """
  @impl true
  @spec evaluate_rag_triad(generation(), keyword()) ::
          {:ok, triad_result()} | {:error, term()}
  def evaluate_rag_triad(generation, opts \\ []) do
    start_time = System.monotonic_time()

    with {:ok, context_relevance} <- evaluate_context_relevance(generation, opts),
         {:ok, groundedness} <- evaluate_groundedness(generation, opts),
         {:ok, answer_relevance} <- evaluate_answer_relevance(generation, opts) do
      overall =
        (context_relevance.score + groundedness.score + answer_relevance.score) / 3.0

      result = %{
        context_relevance: context_relevance,
        groundedness: groundedness,
        answer_relevance: answer_relevance,
        overall: overall
      }

      emit_telemetry(:rag_triad, start_time, generation, result)

      {:ok, result}
    end
  end

  @doc """
  Evaluate context relevance only.

  Measures how well the retrieved context matches the query.
  """
  @impl true
  @spec evaluate_context_relevance(generation(), keyword()) ::
          {:ok, triad_score()} | {:error, term()}
  def evaluate_context_relevance(generation, opts \\ []) do
    prompt = build_context_relevance_prompt(generation)
    evaluate_with_prompt(prompt, opts)
  end

  @doc """
  Evaluate groundedness only.

  Measures how well the response is supported by the context.
  """
  @impl true
  @spec evaluate_groundedness(generation(), keyword()) ::
          {:ok, triad_score()} | {:error, term()}
  def evaluate_groundedness(generation, opts \\ []) do
    prompt = build_groundedness_prompt(generation)
    evaluate_with_prompt(prompt, opts)
  end

  @doc """
  Evaluate answer relevance only.

  Measures how well the response addresses the query.
  """
  @impl true
  @spec evaluate_answer_relevance(generation(), keyword()) ::
          {:ok, triad_score()} | {:error, term()}
  def evaluate_answer_relevance(generation, opts \\ []) do
    prompt = build_answer_relevance_prompt(generation)
    evaluate_with_prompt(prompt, opts)
  end

  @doc """
  Detect if response contains hallucinations.

  Hallucinations are claims in the response that are not supported
  by the provided context.
  """
  @impl true
  @spec detect_hallucination(generation(), keyword()) ::
          {:ok, hallucination_result()} | {:error, term()}
  def detect_hallucination(generation, opts \\ []) do
    start_time = System.monotonic_time()
    prompt = build_hallucination_prompt(generation)

    case Router.complete([%{role: :user, content: prompt}], opts) do
      {:ok, %{content: content}} ->
        case parse_hallucination_response(content) do
          {:ok, result} ->
            emit_telemetry(:hallucination, start_time, generation, result)
            {:ok, result}

          error ->
            error
        end

      {:error, _} = error ->
        error
    end
  end

  # Private functions

  defp evaluate_with_prompt(prompt, opts) do
    case Router.complete([%{role: :user, content: prompt}], opts) do
      {:ok, %{content: content}} ->
        parse_score_response(content)

      {:error, _} = error ->
        error
    end
  end

  defp build_context_relevance_prompt(generation) do
    """
    Evaluate the relevance of the retrieved context to the query.

    Query: #{get_field(generation, :query)}

    Context:
    #{get_field(generation, :context)}

    Score the context relevance from 1-5:
    1 = Very poor - Context is completely unrelated to the query
    2 = Poor - Context is mostly unrelated with minor relevance
    3 = Acceptable - Context is somewhat relevant but missing key information
    4 = Good - Context is mostly relevant and helpful
    5 = Excellent - Context is highly relevant and comprehensive

    Respond with ONLY a JSON object in this exact format:
    {"score": <1-5>, "reasoning": "<explanation>"}
    """
  end

  defp build_groundedness_prompt(generation) do
    """
    Evaluate how well the response is grounded in the provided context.

    Context:
    #{get_field(generation, :context)}

    Response:
    #{get_field(generation, :response)}

    Score the groundedness from 1-5:
    1 = Very poor - Response contains many unsupported claims
    2 = Poor - Response has several claims not in context
    3 = Acceptable - Response is mostly supported with some gaps
    4 = Good - Response is well supported by context
    5 = Excellent - All claims are directly supported by context

    Respond with ONLY a JSON object in this exact format:
    {"score": <1-5>, "reasoning": "<explanation>"}
    """
  end

  defp build_answer_relevance_prompt(generation) do
    """
    Evaluate how well the response addresses the original query.

    Query: #{get_field(generation, :query)}

    Response:
    #{get_field(generation, :response)}

    Score the answer relevance from 1-5:
    1 = Very poor - Response does not address the query at all
    2 = Poor - Response barely addresses the query
    3 = Acceptable - Response partially addresses the query
    4 = Good - Response mostly addresses the query well
    5 = Excellent - Response fully and directly addresses the query

    Respond with ONLY a JSON object in this exact format:
    {"score": <1-5>, "reasoning": "<explanation>"}
    """
  end

  defp build_hallucination_prompt(generation) do
    """
    Analyze if the response contains hallucinations - claims not supported by the context.

    Context:
    #{get_field(generation, :context)}

    Response:
    #{get_field(generation, :response)}

    Determine if the response contains any claims, facts, or statements that are NOT
    supported by or derivable from the provided context.

    Respond with ONLY a JSON object in this exact format:
    {"hallucinating": <true|false>, "evidence": "<explanation of your finding>"}
    """
  end

  defp parse_score_response(content) do
    case extract_json(content) do
      {:ok, %{"score" => score, "reasoning" => reasoning}}
      when score in 1..5 ->
        {:ok, %{score: score, reasoning: reasoning}}

      {:ok, _} ->
        {:error, :invalid_response_format}

      error ->
        error
    end
  end

  defp parse_hallucination_response(content) do
    case extract_json(content) do
      {:ok, %{"hallucinating" => hallucinating, "evidence" => evidence}}
      when is_boolean(hallucinating) ->
        {:ok, %{hallucinating: hallucinating, evidence: evidence}}

      {:ok, _} ->
        {:error, :invalid_response_format}

      error ->
        error
    end
  end

  defp extract_json(content) do
    case Regex.run(~r/\{[^{}]*\}/, content) do
      [json] ->
        case Jason.decode(json) do
          {:ok, map} -> {:ok, map}
          {:error, _} -> {:error, :json_parse_error}
        end

      nil ->
        {:error, :no_json_found}
    end
  end

  defp get_field(generation, field) when is_map(generation) do
    Map.get(generation, field) || Map.get(generation, Atom.to_string(field)) || ""
  end

  defp emit_telemetry(event, start_time, generation, result) do
    duration = System.monotonic_time() - start_time

    :telemetry.execute(
      [:portfolio_manager, :evaluation, event],
      %{duration: duration},
      %{
        generation_id: get_field(generation, :id),
        result: result
      }
    )
  end
end
