defmodule PortfolioManager.Generation do
  @moduledoc """
  Unified state container for RAG generation pipeline.

  Tracks the full lifecycle: query -> embedding -> retrieval -> context -> prompt -> response -> evaluation.

  ## Usage

      generation =
        Generation.new("What does this function do?")
        |> Generation.with_embedding(embedding)
        |> Generation.with_retrieval(results)
        |> Generation.with_context(context, sources)
        |> Generation.with_prompt(prompt)
        |> Generation.with_response(response)
        |> Generation.with_evaluation(:groundedness, %{score: 5, reasoning: "..."})

  ## Fields

    * `:id` - UUID for tracking
    * `:query` - Original query string
    * `:query_embedding` - Vector embedding of query
    * `:retrieval_results` - Raw retrieval results
    * `:context` - Assembled context string
    * `:context_sources` - Source references for context
    * `:prompt` - Final prompt sent to LLM
    * `:response` - LLM response
    * `:evaluations` - Map of evaluation results
    * `:metadata` - User-defined metadata
    * `:halted?` - Whether pipeline was halted
    * `:errors` - List of errors encountered
  """

  @type t :: %__MODULE__{
          id: String.t(),
          query: String.t(),
          query_embedding: [float()] | nil,
          retrieval_results: [map()] | nil,
          context: String.t() | nil,
          context_sources: [String.t()] | nil,
          prompt: String.t() | nil,
          response: String.t() | nil,
          evaluations: map(),
          metadata: map(),
          halted?: boolean(),
          errors: [term()]
        }

  defstruct [
    :id,
    :query,
    :query_embedding,
    :retrieval_results,
    :context,
    :context_sources,
    :prompt,
    :response,
    evaluations: %{},
    metadata: %{},
    halted?: false,
    errors: []
  ]

  @doc """
  Create a new generation with a query.

  ## Options

    * `:metadata` - User-defined metadata map (default: %{})
  """
  @spec new(String.t(), keyword()) :: t()
  def new(query, opts \\ []) do
    metadata = Keyword.get(opts, :metadata, %{})

    %__MODULE__{
      id: generate_id(),
      query: query,
      metadata: metadata
    }
  end

  @doc """
  Add embedding to generation.
  """
  @spec with_embedding(t(), [float()]) :: t()
  def with_embedding(%__MODULE__{} = gen, embedding) do
    %{gen | query_embedding: embedding}
  end

  @doc """
  Add retrieval results to generation.
  """
  @spec with_retrieval(t(), [map()]) :: t()
  def with_retrieval(%__MODULE__{} = gen, results) do
    %{gen | retrieval_results: results}
  end

  @doc """
  Add context and sources to generation.
  """
  @spec with_context(t(), String.t(), [String.t()]) :: t()
  def with_context(%__MODULE__{} = gen, context, sources) do
    %{gen | context: context, context_sources: sources}
  end

  @doc """
  Add prompt to generation.
  """
  @spec with_prompt(t(), String.t()) :: t()
  def with_prompt(%__MODULE__{} = gen, prompt) do
    %{gen | prompt: prompt}
  end

  @doc """
  Add response to generation.
  """
  @spec with_response(t(), String.t()) :: t()
  def with_response(%__MODULE__{} = gen, response) do
    %{gen | response: response}
  end

  @doc """
  Add an evaluation result to generation.
  """
  @spec with_evaluation(t(), atom(), map()) :: t()
  def with_evaluation(%__MODULE__{} = gen, name, result) do
    %{gen | evaluations: Map.put(gen.evaluations, name, result)}
  end

  @doc """
  Halt the generation with a reason.

  Marks the generation as halted and adds the reason to errors.
  """
  @spec halt(t(), term()) :: t()
  def halt(%__MODULE__{} = gen, reason) do
    %{gen | halted?: true, errors: [reason | gen.errors]}
  end

  @doc """
  Add an error without halting.
  """
  @spec add_error(t(), term()) :: t()
  def add_error(%__MODULE__{} = gen, error) do
    %{gen | errors: [error | gen.errors]}
  end

  @doc """
  Check if generation completed successfully.

  Returns true when not halted and has a response.
  """
  @spec success?(t()) :: boolean()
  def success?(%__MODULE__{halted?: true}), do: false
  def success?(%__MODULE__{response: nil}), do: false
  def success?(%__MODULE__{}), do: true

  defp generate_id do
    :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
  end
end
