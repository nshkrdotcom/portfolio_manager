# Advanced RAG Patterns: Self-RAG, CRAG, and Agentic Retrieval

**Expert:** Dr. Michael Tanaka, Senior Fellow ML Researcher
**Experience:** Anthropic, Google DeepMind, NeurIPS/ICML Publications

---

## Table of Contents

1. [RAG Evolution Overview](#rag-evolution-overview)
2. [Self-RAG: Self-Reflective Retrieval](#self-rag-self-reflective-retrieval)
3. [CRAG: Corrective Retrieval](#crag-corrective-retrieval)
4. [Agentic RAG](#agentic-rag)
5. [GraphRAG Patterns](#graphrag-patterns)
6. [Multi-Hop Retrieval](#multi-hop-retrieval)
7. [Evaluation Framework](#evaluation-framework)
8. [Recommended Architecture](#recommended-architecture)

---

## 1. RAG Evolution Overview

### 1.1 RAG Generations

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         RAG EVOLUTION                                    │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                          │
│  Gen 1: Naive RAG                                                       │
│  ┌────────┐    ┌────────┐    ┌────────┐                                │
│  │ Query  │───▶│Retrieve│───▶│Generate│                                │
│  └────────┘    └────────┘    └────────┘                                │
│  Problem: Retrieved chunks may be irrelevant                            │
│                                                                          │
│  Gen 2: Advanced RAG                                                    │
│  ┌────────┐    ┌────────┐    ┌────────┐    ┌────────┐    ┌────────┐   │
│  │ Query  │───▶│Retrieve│───▶│ Rerank │───▶│ Filter │───▶│Generate│   │
│  └────────┘    └────────┘    └────────┘    └────────┘    └────────┘   │
│  Problem: Still no verification of answer quality                       │
│                                                                          │
│  Gen 3: Self-RAG / CRAG                                                 │
│  ┌────────┐    ┌────────┐    ┌────────┐    ┌────────┐                  │
│  │ Query  │───▶│Retrieve│───▶│Generate│───▶│Critique│───┐              │
│  └────────┘    └────────┘    └────────┘    └────────┘   │              │
│       ▲                                                  │              │
│       └──────────────────────────────────────────────────┘              │
│  Improvement: Self-correction and retrieval refinement                  │
│                                                                          │
│  Gen 4: Agentic RAG                                                     │
│  ┌────────┐    ┌────────┐    ┌────────┐    ┌────────┐                  │
│  │ Query  │───▶│ Plan   │───▶│Execute │───▶│Reflect │───▶ Answer       │
│  └────────┘    └────────┘    │ Tools  │    └────────┘                  │
│                              └────┬───┘                                 │
│                                   │ (search, compute, lookup)           │
│  Improvement: Dynamic tool use and multi-step reasoning                 │
│                                                                          │
└─────────────────────────────────────────────────────────────────────────┘
```

### 1.2 Pattern Selection Guide

| Pattern | Best For | Complexity | Latency |
|---------|----------|------------|---------|
| **Naive RAG** | Simple Q&A | Low | Low |
| **Hybrid RAG** | General use | Medium | Medium |
| **Self-RAG** | Accuracy-critical | High | High |
| **CRAG** | Knowledge-intensive | High | High |
| **Agentic** | Complex reasoning | Very High | Variable |
| **GraphRAG** | Entity-rich domains | High | Medium |

---

## 2. Self-RAG: Self-Reflective Retrieval

### 2.1 Concept

Self-RAG adds reflection tokens during generation:
- **[Retrieve]**: Should I retrieve for this segment?
- **[IsRel]**: Is the retrieved passage relevant?
- **[IsSup]**: Is the response supported by the passage?
- **[IsUse]**: Is the response useful?

### 2.2 Implementation

```elixir
defmodule PortfolioManager.RAG.SelfRAG do
  @moduledoc """
  Self-reflective RAG with retrieval and generation critique.
  """

  @retrieval_threshold 0.7
  @relevance_threshold 0.6
  @support_threshold 0.7

  defstruct [
    :retriever,
    :generator,
    :critic,
    :max_iterations
  ]

  @type reflection :: %{
    should_retrieve: boolean(),
    is_relevant: float(),
    is_supported: float(),
    is_useful: float()
  }

  @doc """
  Execute Self-RAG query with reflection.
  """
  def query(self_rag, query_text, opts \\ []) do
    max_iterations = opts[:max_iterations] || self_rag.max_iterations || 3

    initial_state = %{
      query: query_text,
      retrieved: [],
      generated_segments: [],
      reflections: [],
      iteration: 0
    }

    do_self_rag(self_rag, initial_state, max_iterations)
  end

  defp do_self_rag(_self_rag, state, max_iter) when state.iteration >= max_iter do
    finalize_response(state)
  end

  defp do_self_rag(self_rag, state, max_iterations) do
    # Step 1: Decide if retrieval is needed
    retrieval_decision = should_retrieve?(self_rag.critic, state)

    state = if retrieval_decision.should_retrieve do
      # Step 2: Retrieve and filter by relevance
      {:ok, candidates} = self_rag.retriever.search(state.query, limit: 10)

      relevant = candidates
      |> Enum.map(fn chunk ->
        relevance = assess_relevance(self_rag.critic, state.query, chunk)
        {chunk, relevance}
      end)
      |> Enum.filter(fn {_, score} -> score >= @relevance_threshold end)
      |> Enum.map(fn {chunk, _} -> chunk end)

      %{state | retrieved: state.retrieved ++ relevant}
    else
      state
    end

    # Step 3: Generate response segment
    context = build_context(state.retrieved)
    {:ok, segment} = generate_segment(self_rag.generator, state.query, context)

    # Step 4: Assess support and usefulness
    reflection = %{
      should_retrieve: retrieval_decision.should_retrieve,
      is_relevant: avg_relevance(state.retrieved),
      is_supported: assess_support(self_rag.critic, segment, state.retrieved),
      is_useful: assess_usefulness(self_rag.critic, state.query, segment)
    }

    new_state = %{state |
      generated_segments: state.generated_segments ++ [segment],
      reflections: state.reflections ++ [reflection],
      iteration: state.iteration + 1
    }

    # Step 5: Decide to continue or stop
    if should_continue?(reflection) do
      # Refine query based on reflection
      refined_query = refine_query(self_rag.generator, state.query, segment, reflection)
      do_self_rag(self_rag, %{new_state | query: refined_query}, max_iterations)
    else
      finalize_response(new_state)
    end
  end

  defp should_retrieve?(critic, state) do
    prompt = """
    Given the query and current context, should we retrieve more information?

    Query: #{state.query}
    Current context length: #{length(state.retrieved)} passages

    Output a JSON with:
    - should_retrieve: boolean
    - reason: string
    """

    {:ok, response} = critic.analyze(prompt)
    parse_retrieval_decision(response)
  end

  defp assess_relevance(critic, query, chunk) do
    prompt = """
    Rate the relevance of this passage to the query on a scale of 0 to 1.

    Query: #{query}
    Passage: #{chunk.content}

    Output only a number between 0 and 1.
    """

    {:ok, response} = critic.analyze(prompt)
    parse_float(response)
  end

  defp assess_support(critic, segment, retrieved) do
    context = Enum.map_join(retrieved, "\n\n", & &1.content)

    prompt = """
    Rate how well the response is supported by the retrieved passages (0 to 1).

    Retrieved passages:
    #{context}

    Response: #{segment}

    Output only a number between 0 and 1.
    """

    {:ok, response} = critic.analyze(prompt)
    parse_float(response)
  end

  defp assess_usefulness(critic, query, segment) do
    prompt = """
    Rate how useful this response is for answering the query (0 to 1).

    Query: #{query}
    Response: #{segment}

    Output only a number between 0 and 1.
    """

    {:ok, response} = critic.analyze(prompt)
    parse_float(response)
  end

  defp should_continue?(reflection) do
    reflection.is_supported < @support_threshold or
      reflection.is_useful < 0.7
  end

  defp refine_query(generator, original_query, last_segment, reflection) do
    if reflection.is_supported < @support_threshold do
      # Need more specific information
      prompt = """
      The response lacked support. Generate a more specific query.

      Original: #{original_query}
      Last response: #{last_segment}

      New query:
      """

      {:ok, refined} = generator.generate(prompt)
      refined
    else
      original_query
    end
  end

  defp finalize_response(state) do
    combined = Enum.join(state.generated_segments, "\n\n")

    {:ok, %{
      answer: combined,
      sources: state.retrieved,
      reflections: state.reflections,
      iterations: state.iteration
    }}
  end

  defp build_context(chunks) do
    Enum.map_join(chunks, "\n\n---\n\n", & &1.content)
  end

  defp generate_segment(generator, query, context) do
    generator.generate(%{query: query, context: context})
  end

  defp parse_retrieval_decision(response) do
    # Parse JSON response
    %{should_retrieve: true, reason: ""}
  end

  defp parse_float(string) do
    case Float.parse(String.trim(string)) do
      {float, _} -> float
      :error -> 0.5
    end
  end

  defp avg_relevance([]), do: 0.0
  defp avg_relevance(chunks) do
    # Would calculate average relevance score
    0.8
  end
end
```

---

## 3. CRAG: Corrective Retrieval

### 3.1 CRAG Flow

```
Query ───▶ Retrieve ───▶ Evaluate Relevance
                              │
           ┌──────────────────┼──────────────────┐
           ▼                  ▼                  ▼
      [Correct]          [Ambiguous]        [Incorrect]
           │                  │                  │
           ▼                  ▼                  ▼
     Use Retrieved      Knowledge         Web Search
        Chunks         Refinement         (Fallback)
           │                  │                  │
           └──────────────────┴──────────────────┘
                              │
                              ▼
                    Knowledge Refinement
                              │
                              ▼
                    Final Generation
```

### 3.2 Implementation

```elixir
defmodule PortfolioManager.RAG.CRAG do
  @moduledoc """
  Corrective Retrieval Augmented Generation.
  Evaluates retrieval quality and applies corrective actions.
  """

  @correct_threshold 0.7
  @incorrect_threshold 0.3

  defstruct [
    :retriever,
    :evaluator,
    :generator,
    :web_search,
    :knowledge_refiner
  ]

  @doc """
  Execute CRAG query.
  """
  def query(crag, query_text, opts \\ []) do
    # Step 1: Initial retrieval
    {:ok, retrieved} = crag.retriever.search(query_text, limit: 10)

    # Step 2: Evaluate retrieval quality
    evaluation = evaluate_retrieval(crag.evaluator, query_text, retrieved)

    # Step 3: Apply corrective action based on evaluation
    refined_knowledge = case evaluation.action do
      :correct ->
        # High quality - use retrieved directly
        {:ok, retrieved}

      :ambiguous ->
        # Mixed quality - refine with knowledge decomposition
        refine_knowledge(crag.knowledge_refiner, query_text, retrieved)

      :incorrect ->
        # Low quality - fallback to web search
        web_search_fallback(crag.web_search, query_text, retrieved)
    end

    # Step 4: Generate final response
    case refined_knowledge do
      {:ok, knowledge} ->
        context = build_context(knowledge)
        crag.generator.generate(%{query: query_text, context: context})

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp evaluate_retrieval(evaluator, query, retrieved) do
    # Score each retrieved chunk
    scores = Enum.map(retrieved, fn chunk ->
      score_chunk(evaluator, query, chunk)
    end)

    avg_score = Enum.sum(scores) / max(length(scores), 1)
    correct_count = Enum.count(scores, &(&1 >= @correct_threshold))
    incorrect_count = Enum.count(scores, &(&1 <= @incorrect_threshold))

    action = cond do
      correct_count >= length(scores) * 0.7 -> :correct
      incorrect_count >= length(scores) * 0.5 -> :incorrect
      true -> :ambiguous
    end

    %{
      action: action,
      avg_score: avg_score,
      scores: scores,
      correct_count: correct_count,
      incorrect_count: incorrect_count
    }
  end

  defp score_chunk(evaluator, query, chunk) do
    prompt = """
    Rate how relevant and accurate this passage is for answering the query.

    Query: #{query}
    Passage: #{chunk.content}

    Consider:
    1. Direct relevance to the question
    2. Factual accuracy (if verifiable)
    3. Completeness of information

    Output a score from 0 to 1.
    """

    {:ok, response} = evaluator.analyze(prompt)
    parse_score(response)
  end

  defp refine_knowledge(refiner, query, retrieved) do
    # Knowledge decomposition and refinement
    prompt = """
    The retrieved passages have mixed relevance. Extract and refine
    only the relevant knowledge for this query.

    Query: #{query}

    Passages:
    #{format_passages(retrieved)}

    Output refined knowledge as bullet points, keeping only relevant facts.
    """

    case refiner.refine(prompt) do
      {:ok, refined_text} ->
        # Convert refined text back to chunk format
        refined_chunk = %{
          content: refined_text,
          metadata: %{source: :refined, original_count: length(retrieved)}
        }
        {:ok, [refined_chunk]}

      error ->
        error
    end
  end

  defp web_search_fallback(web_search, query, original_retrieved) do
    # Query web for additional information
    case web_search.search(query, limit: 5) do
      {:ok, web_results} ->
        # Combine web results with any useful original results
        combined = web_results ++ Enum.take(original_retrieved, 2)
        {:ok, combined}

      {:error, _} ->
        # Fall back to original even if low quality
        {:ok, original_retrieved}
    end
  end

  defp build_context(chunks) do
    Enum.map_join(chunks, "\n\n---\n\n", & &1.content)
  end

  defp format_passages(chunks) do
    chunks
    |> Enum.with_index(1)
    |> Enum.map_join("\n\n", fn {chunk, idx} ->
      "[#{idx}] #{chunk.content}"
    end)
  end

  defp parse_score(response) do
    case Float.parse(String.trim(response)) do
      {score, _} when score >= 0 and score <= 1 -> score
      _ -> 0.5
    end
  end
end
```

---

## 4. Agentic RAG

### 4.1 Agent Architecture

```elixir
defmodule PortfolioManager.RAG.AgenticRAG do
  @moduledoc """
  Agent-based RAG with tool use and multi-step reasoning.
  """

  defstruct [
    :planner,
    :executor,
    :tools,
    :memory,
    :max_steps
  ]

  @doc """
  Available tools for the agent.
  """
  def default_tools do
    %{
      search_docs: &Tools.search_docs/1,
      search_code: &Tools.search_code/1,
      search_graph: &Tools.search_graph/1,
      get_file: &Tools.get_file/1,
      run_query: &Tools.run_query/1,
      calculate: &Tools.calculate/1,
      summarize: &Tools.summarize/1
    }
  end

  @doc """
  Execute agentic query.
  """
  def query(agent, query_text, opts \\ []) do
    # Initialize agent state
    state = %{
      query: query_text,
      plan: nil,
      steps_executed: [],
      observations: [],
      memory: agent.memory,
      iteration: 0
    }

    # Step 1: Plan the approach
    {:ok, plan} = create_plan(agent.planner, query_text)
    state = %{state | plan: plan}

    # Step 2: Execute plan with reflection
    execute_plan(agent, state, agent.max_steps || 10)
  end

  defp create_plan(planner, query) do
    prompt = """
    Create a step-by-step plan to answer this question.
    Available tools: search_docs, search_code, search_graph, get_file, calculate, summarize

    Question: #{query}

    Output a JSON array of steps, each with:
    - tool: which tool to use
    - input: input for the tool
    - purpose: why this step is needed

    Example:
    [
      {"tool": "search_docs", "input": "authentication flow", "purpose": "Find auth documentation"},
      {"tool": "search_code", "input": "login function", "purpose": "Find implementation details"}
    ]
    """

    {:ok, response} = planner.plan(prompt)
    parse_plan(response)
  end

  defp execute_plan(agent, state, remaining_steps) when remaining_steps <= 0 do
    synthesize_answer(agent, state)
  end

  defp execute_plan(agent, state, remaining_steps) do
    case get_next_step(state) do
      nil ->
        # Plan complete, synthesize answer
        synthesize_answer(agent, state)

      step ->
        # Execute step
        observation = execute_step(agent, step)

        new_state = %{state |
          steps_executed: state.steps_executed ++ [step],
          observations: state.observations ++ [observation],
          iteration: state.iteration + 1
        }

        # Reflect and possibly replan
        case reflect_on_progress(agent, new_state) do
          {:continue, state} ->
            execute_plan(agent, state, remaining_steps - 1)

          {:replan, new_plan, state} ->
            execute_plan(agent, %{state | plan: new_plan}, remaining_steps - 1)

          {:done, state} ->
            synthesize_answer(agent, state)
        end
    end
  end

  defp get_next_step(state) do
    executed_count = length(state.steps_executed)
    plan_steps = state.plan[:steps] || []

    if executed_count < length(plan_steps) do
      Enum.at(plan_steps, executed_count)
    else
      nil
    end
  end

  defp execute_step(agent, step) do
    tool = Map.get(agent.tools, String.to_atom(step["tool"]))

    if tool do
      case tool.(step["input"]) do
        {:ok, result} ->
          %{
            step: step,
            success: true,
            result: result,
            timestamp: DateTime.utc_now()
          }

        {:error, reason} ->
          %{
            step: step,
            success: false,
            error: reason,
            timestamp: DateTime.utc_now()
          }
      end
    else
      %{
        step: step,
        success: false,
        error: "Unknown tool: #{step["tool"]}",
        timestamp: DateTime.utc_now()
      }
    end
  end

  defp reflect_on_progress(agent, state) do
    observations_summary = summarize_observations(state.observations)

    prompt = """
    Reflect on progress toward answering the original question.

    Original question: #{state.query}

    Steps executed: #{length(state.steps_executed)}
    Observations: #{observations_summary}

    Decide:
    1. CONTINUE - more steps needed from current plan
    2. REPLAN - need a different approach
    3. DONE - have enough information to answer

    Output JSON: {"decision": "CONTINUE|REPLAN|DONE", "reason": "..."}
    """

    {:ok, response} = agent.executor.analyze(prompt)

    case parse_reflection(response) do
      %{decision: "CONTINUE"} -> {:continue, state}
      %{decision: "REPLAN"} ->
        {:ok, new_plan} = create_replan(agent.planner, state)
        {:replan, new_plan, state}
      %{decision: "DONE"} -> {:done, state}
    end
  end

  defp create_replan(planner, state) do
    prompt = """
    The original plan didn't work well. Create a new plan.

    Original question: #{state.query}
    What we've learned: #{summarize_observations(state.observations)}

    Create a new plan with different tools or approaches.
    """

    {:ok, response} = planner.plan(prompt)
    parse_plan(response)
  end

  defp synthesize_answer(agent, state) do
    context = state.observations
    |> Enum.filter(& &1.success)
    |> Enum.map(& &1.result)
    |> Enum.join("\n\n---\n\n")

    prompt = """
    Synthesize a complete answer to the question.

    Question: #{state.query}

    Information gathered:
    #{context}

    Provide a comprehensive answer citing the sources.
    """

    {:ok, answer} = agent.executor.generate(prompt)

    {:ok, %{
      answer: answer,
      steps: state.steps_executed,
      observations: state.observations,
      iterations: state.iteration
    }}
  end

  defp summarize_observations(observations) do
    observations
    |> Enum.map(fn obs ->
      if obs.success do
        "#{obs.step["tool"]}: Found #{String.length(inspect(obs.result))} chars"
      else
        "#{obs.step["tool"]}: Failed - #{obs.error}"
      end
    end)
    |> Enum.join("\n")
  end

  defp parse_plan(response) do
    # Parse JSON plan
    {:ok, %{steps: []}}
  end

  defp parse_reflection(response) do
    # Parse reflection decision
    %{decision: "CONTINUE"}
  end
end

defmodule PortfolioManager.RAG.AgenticRAG.Tools do
  @moduledoc """
  Tools available to the agentic RAG system.
  """

  def search_docs(query) do
    # Search document vectors
    {:ok, []}
  end

  def search_code(query) do
    # Search code vectors
    {:ok, []}
  end

  def search_graph(query) do
    # Search graph entities
    {:ok, []}
  end

  def get_file(path) do
    # Read specific file
    case File.read(path) do
      {:ok, content} -> {:ok, content}
      {:error, reason} -> {:error, reason}
    end
  end

  def run_query(cypher) do
    # Execute graph query
    {:ok, []}
  end

  def calculate(expression) do
    # Safe calculation
    {:ok, 0}
  end

  def summarize(text) do
    # LLM summarization
    {:ok, text}
  end
end
```

---

## 5. GraphRAG Patterns

### 5.1 Local vs Global Retrieval

```elixir
defmodule PortfolioManager.RAG.GraphRAG do
  @moduledoc """
  Graph-based RAG with local and global retrieval modes.
  """

  @doc """
  Local retrieval: Start from entities in query, expand outward.
  """
  def local_retrieval(query, opts \\ []) do
    depth = opts[:depth] || 2
    graph_id = opts[:graph_id]

    with {:ok, embedding} <- embed_query(query),
         {:ok, seed_entities} <- find_seed_entities(embedding, graph_id),
         {:ok, expanded} <- expand_entities(seed_entities, depth, graph_id) do
      build_local_context(seed_entities, expanded)
    end
  end

  @doc """
  Global retrieval: Use community summaries for high-level context.
  """
  def global_retrieval(query, opts \\ []) do
    graph_id = opts[:graph_id]
    max_communities = opts[:max_communities] || 5

    with {:ok, embedding} <- embed_query(query),
         {:ok, communities} <- search_communities(embedding, graph_id, max_communities) do
      build_global_context(communities)
    end
  end

  @doc """
  Hybrid: Combine local entities with global community context.
  """
  def hybrid_retrieval(query, opts \\ []) do
    local_weight = opts[:local_weight] || 0.6
    global_weight = opts[:global_weight] || 0.4

    with {:ok, local_ctx} <- local_retrieval(query, opts),
         {:ok, global_ctx} <- global_retrieval(query, opts) do
      combined = %{
        entities: local_ctx.entities,
        relationships: local_ctx.relationships,
        communities: global_ctx.communities,
        weights: %{local: local_weight, global: global_weight}
      }

      {:ok, combined}
    end
  end

  defp find_seed_entities(embedding, graph_id) do
    # Vector search over entity embeddings
    {:ok, []}
  end

  defp expand_entities(entities, depth, graph_id) do
    # BFS/DFS expansion from seed entities
    {:ok, []}
  end

  defp search_communities(embedding, graph_id, limit) do
    # Search community summary embeddings
    {:ok, []}
  end

  defp build_local_context(seed, expanded) do
    {:ok, %{
      entities: seed ++ expanded,
      relationships: extract_relationships(seed, expanded)
    }}
  end

  defp build_global_context(communities) do
    {:ok, %{
      communities: communities,
      summaries: Enum.map(communities, & &1.summary)
    }}
  end

  defp extract_relationships(_seed, _expanded), do: []
  defp embed_query(_query), do: {:ok, []}
end
```

---

## 6. Multi-Hop Retrieval

```elixir
defmodule PortfolioManager.RAG.MultiHop do
  @moduledoc """
  Multi-hop retrieval for complex questions requiring reasoning chains.
  """

  @doc """
  Decompose question and retrieve iteratively.
  """
  def query(question, opts \\ []) do
    max_hops = opts[:max_hops] || 4

    # Step 1: Decompose question into sub-questions
    {:ok, sub_questions} = decompose_question(question)

    # Step 2: Iteratively answer sub-questions
    state = %{
      original_question: question,
      sub_questions: sub_questions,
      answers: %{},
      context: [],
      hop: 0
    }

    execute_hops(state, max_hops)
  end

  defp decompose_question(question) do
    prompt = """
    Break this complex question into simpler sub-questions that can be answered independently.

    Question: #{question}

    Output as JSON array: ["sub-question 1", "sub-question 2", ...]
    """

    # Would call LLM
    {:ok, [question]}
  end

  defp execute_hops(state, max_hops) when state.hop >= max_hops do
    synthesize_final_answer(state)
  end

  defp execute_hops(state, max_hops) do
    current_sub_q = Enum.at(state.sub_questions, state.hop)

    if current_sub_q do
      # Retrieve for this sub-question, considering previous context
      {:ok, retrieved} = retrieve_with_context(current_sub_q, state.context)

      # Answer sub-question
      {:ok, answer} = answer_sub_question(current_sub_q, retrieved, state.answers)

      new_state = %{state |
        answers: Map.put(state.answers, state.hop, %{question: current_sub_q, answer: answer}),
        context: state.context ++ retrieved,
        hop: state.hop + 1
      }

      execute_hops(new_state, max_hops)
    else
      synthesize_final_answer(state)
    end
  end

  defp retrieve_with_context(question, previous_context) do
    # Enhance query with previous findings
    enhanced_query = if previous_context == [] do
      question
    else
      context_summary = summarize_context(previous_context)
      "#{question} (Context: #{context_summary})"
    end

    # Retrieve
    {:ok, []}
  end

  defp answer_sub_question(question, retrieved, previous_answers) do
    context = format_context(retrieved)
    previous = format_previous_answers(previous_answers)

    prompt = """
    Answer this question using the provided context.

    Previous findings:
    #{previous}

    Current context:
    #{context}

    Question: #{question}

    Answer:
    """

    # Would call LLM
    {:ok, "answer"}
  end

  defp synthesize_final_answer(state) do
    all_answers = state.answers
    |> Map.values()
    |> Enum.map(fn %{question: q, answer: a} -> "Q: #{q}\nA: #{a}" end)
    |> Enum.join("\n\n")

    prompt = """
    Synthesize a final answer to the original question using these intermediate findings.

    Original question: #{state.original_question}

    Intermediate findings:
    #{all_answers}

    Final answer:
    """

    # Would call LLM
    {:ok, %{
      answer: "final answer",
      reasoning_chain: state.answers,
      hops: state.hop
    }}
  end

  defp summarize_context(context) do
    # Summarize previous context
    "previous context summary"
  end

  defp format_context(retrieved) do
    Enum.map_join(retrieved, "\n", & &1.content)
  end

  defp format_previous_answers(answers) do
    answers
    |> Map.values()
    |> Enum.map(fn %{answer: a} -> a end)
    |> Enum.join("\n")
  end
end
```

---

## 7. Evaluation Framework

```elixir
defmodule PortfolioManager.RAG.Evaluation do
  @moduledoc """
  Comprehensive RAG evaluation metrics.
  """

  @doc """
  Evaluate retrieval quality.
  """
  def evaluate_retrieval(retrieved, ground_truth) do
    %{
      precision_at_k: precision_at_k(retrieved, ground_truth, 10),
      recall_at_k: recall_at_k(retrieved, ground_truth, 10),
      mrr: mean_reciprocal_rank(retrieved, ground_truth),
      ndcg: normalized_dcg(retrieved, ground_truth)
    }
  end

  @doc """
  Evaluate generation quality.
  """
  def evaluate_generation(answer, context, ground_truth) do
    %{
      faithfulness: evaluate_faithfulness(answer, context),
      relevance: evaluate_relevance(answer, ground_truth.question),
      correctness: evaluate_correctness(answer, ground_truth.answer)
    }
  end

  defp precision_at_k(retrieved, ground_truth, k) do
    top_k = Enum.take(retrieved, k) |> Enum.map(& &1.id)
    relevant = MapSet.new(ground_truth)

    hits = Enum.count(top_k, &MapSet.member?(relevant, &1))
    hits / k
  end

  defp recall_at_k(retrieved, ground_truth, k) do
    top_k = Enum.take(retrieved, k) |> Enum.map(& &1.id) |> MapSet.new()
    relevant = ground_truth

    hits = Enum.count(relevant, &MapSet.member?(top_k, &1))
    hits / max(length(relevant), 1)
  end

  defp mean_reciprocal_rank(retrieved, ground_truth) do
    relevant = MapSet.new(ground_truth)

    case Enum.find_index(retrieved, &MapSet.member?(relevant, &1.id)) do
      nil -> 0.0
      idx -> 1 / (idx + 1)
    end
  end

  defp normalized_dcg(retrieved, ground_truth) do
    # Simplified NDCG
    1.0
  end

  defp evaluate_faithfulness(answer, context) do
    # Check if claims in answer are supported by context
    # Would use LLM-as-judge
    1.0
  end

  defp evaluate_relevance(answer, question) do
    # Check if answer addresses the question
    1.0
  end

  defp evaluate_correctness(answer, ground_truth_answer) do
    # Compare to ground truth
    1.0
  end
end
```

---

## 8. Recommended Architecture

### Pattern Selection Decision Tree

```
                        Query Complexity?
                              │
              ┌───────────────┼───────────────┐
              ▼               ▼               ▼
           Simple         Medium          Complex
              │               │               │
              ▼               ▼               ▼
         Hybrid RAG      Self-RAG or    Agentic RAG
                         GraphRAG

        Accuracy Critical?
              │
       ┌──────┴──────┐
       ▼             ▼
      Yes           No
       │             │
       ▼             ▼
    Self-RAG    Hybrid RAG
    or CRAG

        Entity-Rich Domain?
              │
       ┌──────┴──────┐
       ▼             ▼
      Yes           No
       │             │
       ▼             ▼
    GraphRAG    Vector RAG
```

### Recommended Defaults

1. **Start with Hybrid RAG** (vector + BM25)
2. **Add GraphRAG** when entity relationships matter
3. **Use Self-RAG** for accuracy-critical applications
4. **Use Agentic RAG** for complex multi-step reasoning
5. **Use CRAG** when retrieval quality is uncertain

---

## Summary

This document covers advanced RAG patterns:

1. **Self-RAG**: Self-reflection during generation
2. **CRAG**: Corrective actions based on retrieval quality
3. **Agentic RAG**: Tool-using agents for complex queries
4. **GraphRAG**: Entity-centric retrieval with communities
5. **Multi-Hop**: Iterative retrieval for reasoning chains

Each pattern has trade-offs between complexity, latency, and quality.
