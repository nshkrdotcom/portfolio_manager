# Implementation Prompt: Portfolio Manager v0.4.0

**Date:** 2025-12-28
**Objective:** Implement rag_ex feature parity for portfolio_manager

**Greenfield stance:** v0.4.0 is greenfield. Breaking changes are acceptable; prioritize rag_ex and `portfolio_core` port parity over legacy APIs.

---

## REQUIRED READING

Before implementing, read these files in order:

### Gap Analysis
- `/home/home/p/g/n/portfolio_manager/docs/20251228/gap_analysis/gap_analysis.md`

### PortfolioCore Port Contracts (align APIs)
- `/home/home/p/g/n/portfolio_core/lib/portfolio_core/ports/agent.ex`
- `/home/home/p/g/n/portfolio_core/lib/portfolio_core/ports/router.ex`
- `/home/home/p/g/n/portfolio_core/lib/portfolio_core/ports/evaluation.ex`

### Current Source Files (to modify)
- `/home/home/p/g/n/portfolio_manager/lib/portfolio_manager/agent/session.ex`
- `/home/home/p/g/n/portfolio_manager/lib/portfolio_manager/agent/tool.ex`
- `/home/home/p/g/n/portfolio_manager/lib/portfolio_manager/agent.ex`
- `/home/home/p/g/n/portfolio_manager/lib/portfolio_manager/router.ex`
- `/home/home/p/g/n/portfolio_manager/lib/portfolio_manager/pipeline.ex`
- `/home/home/p/g/n/portfolio_manager/lib/portfolio_manager/rag.ex`

### Existing Tests (to extend)
- `/home/home/p/g/n/portfolio_manager/test/agent_test.exs`
- `/home/home/p/g/n/portfolio_manager/test/agent/tool_test.exs`
- `/home/home/p/g/n/portfolio_manager/test/router_test.exs`
- `/home/home/p/g/n/portfolio_manager/test/pipeline_test.exs`

### Configuration Files
- `/home/home/p/g/n/portfolio_manager/mix.exs`
- `/home/home/p/g/n/portfolio_manager/README.md`
- `/home/home/p/g/n/portfolio_manager/CHANGELOG.md`

### Test Support
- `/home/home/p/g/n/portfolio_manager/test/test_helper.exs`
- `/home/home/p/g/n/portfolio_manager/test/support/mocks.ex`

---

## CONTEXT

Portfolio Manager v0.3.0 provides:
- Agent framework with tools (search_code, read_file, list_files, get_graph_context)
- Multi-provider Router with strategies (fallback, round_robin, specialist, cost_optimized)
- Pipeline orchestration with DAG-based execution and caching
- RAG interface delegating to portfolio_index

**Gaps identified against rag_ex:**
1. Evaluation module - entirely missing (RAG triad + hallucination detection)
2. Generation struct - entirely missing (unified RAG state container)
3. Session - missing context, metadata, token_estimate, helper functions
4. Agent - missing process/3, process_with_tools/4, with_context/2, improved tool parsing
5. Router - missing route/2, execute/2, execute_with_retry/2, report_result/3, next_provider/2
6. Strategies - need failure tracking, keyword detection
7. Pipeline - needs parallel execution, on_error policies

---

## IMPLEMENTATION TASKS

### Phase 1: New Core Modules (P1)

#### Task 1.1: Create Evaluation Module

**File:** `/home/home/p/g/n/portfolio_manager/lib/portfolio_manager/evaluation.ex`

```elixir
defmodule PortfolioManager.Evaluation do
  @moduledoc """
  RAG evaluation using the RAG triad: context relevance, groundedness, answer relevance.

  Provides quality assessment for RAG responses with scores 1-5 and reasoning.
  """

  @behaviour PortfolioCore.Ports.Evaluation

  # Implement:
  # - evaluate_rag_triad(generation, opts \\ []) ->
  #   {:ok,
  #    %{
  #      context_relevance: %{score: 1..5, reasoning: string},
  #      groundedness: %{score: 1..5, reasoning: string},
  #      answer_relevance: %{score: 1..5, reasoning: string},
  #      overall: float
  #    }}
  # - evaluate_context_relevance(generation, opts) -> {:ok, %{score: 1..5, reasoning: string}}
  # - evaluate_groundedness(generation, opts) -> {:ok, %{score: 1..5, reasoning: string}}
  # - evaluate_answer_relevance(generation, opts) -> {:ok, %{score: 1..5, reasoning: string}}
  # - detect_hallucination(generation, opts) ->
  #   {:ok, %{hallucinating: boolean, evidence: string}} | {:error, term}
  # - Telemetry: [:portfolio_manager, :evaluation, :rag_triad]
  # - Telemetry: [:portfolio_manager, :evaluation, :hallucination]
end
```

Use `PortfolioManager.Generation` (or a map conforming to `PortfolioCore.Ports.Evaluation.generation/0`) as the input shape.

**Test File:** `/home/home/p/g/n/portfolio_manager/test/evaluation_test.exs`

TDD approach:
1. Write test for `evaluate_context_relevance/2` with mock LLM
2. Implement `evaluate_context_relevance/2`
3. Write test for `evaluate_groundedness/2`
4. Implement `evaluate_groundedness/2`
5. Write test for `evaluate_answer_relevance/2`
6. Implement `evaluate_answer_relevance/2`
7. Write test for `evaluate_rag_triad/2`
8. Implement `evaluate_rag_triad/2`
9. Write test for `detect_hallucination/2`
10. Implement `detect_hallucination/2`
11. Add telemetry tests

#### Task 1.2: Create Generation Struct

**File:** `/home/home/p/g/n/portfolio_manager/lib/portfolio_manager/generation.ex`

```elixir
defmodule PortfolioManager.Generation do
  @moduledoc """
  Unified state container for RAG generation pipeline.

  Tracks the full lifecycle: query -> embedding -> retrieval -> context -> prompt -> response -> evaluation.
  """

  defstruct [
    :id,                    # UUID
    :query,                 # Original query string
    :query_embedding,       # Vector embedding of query
    :retrieval_results,     # Raw retrieval results
    :context,               # Assembled context string
    :context_sources,       # Source references for context
    :prompt,                # Final prompt sent to LLM
    :response,              # LLM response
    :evaluations,           # Map of evaluation results
    :metadata,              # User-defined metadata
    halted?: false,         # Whether pipeline was halted
    errors: []              # List of errors encountered
  ]

  # Implement:
  # - new(query, opts \\ []) -> %Generation{}
  # - with_embedding(gen, embedding) -> %Generation{}
  # - with_retrieval(gen, results) -> %Generation{}
  # - with_context(gen, context, sources) -> %Generation{}
  # - with_prompt(gen, prompt) -> %Generation{}
  # - with_response(gen, response) -> %Generation{}
  # - with_evaluation(gen, name, result) -> %Generation{}
  # - halt(gen, reason) -> %Generation{}
  # - add_error(gen, error) -> %Generation{}
  # - success?(gen) -> boolean
end
```

Ensure `query`, `context`, `response`, and `context_sources` are populated so the struct can be passed directly into evaluation.

**Test File:** `/home/home/p/g/n/portfolio_manager/test/generation_test.exs`

TDD approach:
1. Write test for `new/2`
2. Implement `new/2`
3. Write tests for each `with_*` function
4. Implement each `with_*` function
5. Write tests for `halt/2`, `add_error/2`, `success?/1`
6. Implement remaining functions

#### Task 1.3: Enhance Session

**File:** `/home/home/p/g/n/portfolio_manager/lib/portfolio_manager/agent/session.ex`

Add to existing struct:
```elixir
defstruct [
  :id,
  :created_at,
  :updated_at,  # NEW: timestamp updated on message/tool changes
  :messages,
  :tool_results, # NEW: List of tool results
  :context,      # NEW: Map for session context
  :metadata      # NEW: Map for session metadata
]
```

Add new functions:
```elixir
# - new(opts \\ []) - accept context: and metadata: options
# - add_tool_result(session, tool_name, result) -> session
# - to_llm_messages(session) -> [%{role: atom, content: string}]
# - token_estimate(session) -> integer (rough: chars/4)
# - message_count(session) -> integer
# - last_messages(session, n) -> [message]
# - clear_messages(session) -> session (keeps context/metadata/tool_results)
# - with_context(session, key, value) -> session
# - get_context(session, key) -> term | nil
```

Normalize messages to include `role`, `content`, `timestamp`, optional `tool_name`, and optional `error`.

**Test File:** `/home/home/p/g/n/portfolio_manager/test/agent/session_test.exs`

TDD approach:
1. Write tests for new struct fields
2. Update struct and `new/0` -> `new/1` (breaking change)
3. Write test for `add_tool_result/3`
4. Implement `add_tool_result/3`
5. Continue for each new function

---

### Phase 2: Module Enhancements (P2)

#### Task 2.1: Enhance Agent

**File:** `/home/home/p/g/n/portfolio_manager/lib/portfolio_manager/agent.ex`

Add new functions:
```elixir
# - process(session, prompt, opts \\ []) -> {:ok, response, session} | {:error, term}
#   Session-based LLM call without tools, uses Router
#
# - process_with_tools(session, prompt, tools, opts \\ []) -> {:ok, response, session} | {:error, term}
#   Agentic loop with tool execution (aligns with PortfolioCore.Ports.Agent)
#
# - run(task, opts \\ []) -> {:ok, response} | {:error, term}
#   Optional wrapper; can be removed or kept as a thin adapter (breaking allowed)
#
# - with_context(session_or_agent, key, value) -> session_or_agent
#   Inject context that persists across iterations
#
# - Implement/align required callbacks if adopting @behaviour PortfolioCore.Ports.Agent
#
# Improve parse_tool_call:
# - Handle nested JSON objects
# - Support both "tool"/"args" and "name"/"arguments" formats
# - Return {:tool_call, name, args} | {:final_answer, answer} | :continue
```

Update tests in `/home/home/p/g/n/portfolio_manager/test/agent_test.exs`

#### Task 2.2: Enhance Router

**File:** `/home/home/p/g/n/portfolio_manager/lib/portfolio_manager/router.ex`

Add new functions:
```elixir
# - route(messages, opts) -> {:ok, provider} | {:error, term}
#   Expose provider selection without execution
#
# - execute(messages, opts) -> {:ok, response} | {:error, term}
#   Route and execute in one call (aligns with PortfolioCore.Ports.Router)
#
# - execute_with_retry(messages, opts) -> {:ok, response} | {:error, term}
#   Retry with fallback providers on failure
#
# - execute_with_provider(provider, messages, opts) -> {:ok, response} | {:error, term}
#   Optional explicit provider execution
#
# - report_result(provider_name, :success | :failure, metadata) -> :ok
#   Update strategy state with result feedback
#
# - next_provider(current_provider, opts) -> {:ok, provider} | {:error, :no_more}
#   Get next fallback provider
#
# - get_provider(name) -> {:ok, provider} | {:error, :not_found}
#   Get provider by name
```

Add to strategy state:
```elixir
# Fallback state enhancement:
# - failure_counts: %{provider_name => count}
# - failure_threshold: integer (default 3)
# - Provider marked unhealthy after threshold failures
#
# Specialist state enhancement:
# - keyword_mappings: %{keyword => capability}
# - Auto-detect task_type from message content
```

Update tests in `/home/home/p/g/n/portfolio_manager/test/router_test.exs`

---

### Phase 3: Pipeline Enhancements (P3)

#### Task 3.1: Enhance Pipeline

**File:** `/home/home/p/g/n/portfolio_manager/lib/portfolio_manager/pipeline.ex`

Add to Step struct:
```elixir
%{
  name: atom(),
  function: fun(),
  depends_on: [atom()],
  timeout: pos_integer(),
  cache: boolean(),
  parallel: boolean(),      # NEW: Can run in parallel with other parallel steps
  on_error: :halt | :continue | {:retry, count}  # NEW: Error handling policy
}
```

Add to Pipeline struct:
```elixir
%{
  name: atom(),
  description: String.t(),  # NEW
  steps: [step()],
  config: map(),            # NEW: Pipeline-level config
  metadata: map(),          # NEW: User metadata
  cache_table: atom(),
  results: map()
}
```

Implement parallel execution:
```elixir
# When multiple steps have no dependencies on each other and parallel: true,
# execute them concurrently using Task.async_stream
```

Update tests in `/home/home/p/g/n/portfolio_manager/test/pipeline_test.exs`

#### Task 3.2: Enhance Tool System

**File:** `/home/home/p/g/n/portfolio_manager/lib/portfolio_manager/agent/tool.ex`

Add behaviour:
```elixir
@callback name() :: atom()
@callback description() :: String.t()
@callback parameters() :: [parameter()]
@callback execute(args :: map(), context :: map()) :: {:ok, term()} | {:error, term()}
```

Add helpers:
```elixir
# - to_spec(tool_module) -> map
# - validate_args(tool_module, args) -> :ok | {:error, reasons}
# - format_for_llm(tools) -> string (OpenAI function format)
```

Add context structure:
```elixir
# Context passed to execute/2:
# %{
#   session_id: String.t(),
#   user_id: String.t() | nil,
#   repo: String.t() | nil,
#   router: module()
# }
```

Update tests in `/home/home/p/g/n/portfolio_manager/test/agent/tool_test.exs`

---

## IMPLEMENTATION ORDER

Execute tasks in this order for optimal TDD flow:

1. **Task 1.2: Generation struct** (no dependencies, foundation)
2. **Task 1.3: Session enhancement** (no dependencies)
3. **Task 1.1: Evaluation module** (uses Router)
4. **Task 2.1: Agent enhancement** (uses Session)
5. **Task 2.2: Router enhancement** (independent)
6. **Task 3.1: Pipeline enhancement** (independent)
7. **Task 3.2: Tool enhancement** (uses Agent)

---

## GOALS

After implementation:

Greenfield means legacy APIs can be removed or renamed; update tests and docs to reflect the new surface area.

1. **No compiler warnings**
   ```bash
   mix compile --warnings-as-errors
   ```

2. **All tests pass**
   ```bash
   mix test
   ```

3. **No dialyzer errors**
   ```bash
   mix dialyzer
   ```

4. **No credo issues**
   ```bash
   mix credo --strict
   ```

5. **Documentation complete**
   - All public functions have @doc
   - All modules have @moduledoc
   - Type specs on all public functions

---

## VERSION BUMP

### mix.exs

Change line 4:
```elixir
@version "0.4.0"
```

### README.md

Update Quick Install section (line 16-25):
```markdown
## Quick Install (0.4.0)

Add the dependency in `mix.exs`:

```elixir
def deps do
  [
    {:portfolio_manager, "~> 0.4.0"}
  ]
end
```

---

## CHANGELOG ENTRY

Add to `/home/home/p/g/n/portfolio_manager/CHANGELOG.md` after line 8 (`## [Unreleased]`):

```markdown
## [0.4.0] - 2025-12-28

### Breaking

- `PortfolioManager.Agent.Session.new/0` replaced by `new/1` (context/metadata supported; message schema normalized)
- `PortfolioManager.Agent.run/2` replaced by session-based `process/3` and `process_with_tools/4`
- `PortfolioManager.Router.complete/2` replaced by `execute/2` and `execute_with_retry/2`
- Tool definitions now require `PortfolioManager.Agent.Tool` behaviour modules

### Added

- `PortfolioManager.Evaluation` - RAG quality evaluation
  - `evaluate_rag_triad/2` - Context relevance, groundedness, answer relevance (1-5 scores with reasoning + overall)
  - `detect_hallucination/2` - Hallucination detection with evidence
  - Telemetry events for evaluation metrics

- `PortfolioManager.Generation` - Unified RAG state container
  - Tracks full lifecycle: query -> embedding -> retrieval -> context -> prompt -> response -> evaluation
  - Builder functions: `with_embedding/2`, `with_retrieval/2`, `with_context/3`, etc.
  - Error tracking and halt support

- `PortfolioManager.Agent.Session` enhancements
  - `context`, `metadata`, `tool_results`, `updated_at` fields for session state
  - `add_tool_result/3` for structured tool results
  - `to_llm_messages/1` for LLM-ready message formatting
  - `token_estimate/1` for rough token counting
  - `last_messages/2` for conversation windowing
  - `clear_messages/1` preserving context and tool results
  - `with_context/3` and `get_context/2` for context management

- `PortfolioManager.Agent` enhancements
  - `process/3` for session-based LLM interaction without tools
  - `process_with_tools/4` for agentic tool loops
  - `with_context/3` for context injection across iterations
  - Improved tool call parsing with nested JSON support

- `PortfolioManager.Router` enhancements
  - `route/2` exposes provider selection
  - `execute/2` for route + execute in one call
  - `execute_with_retry/2` for retry/fallback execution
  - `report_result/3` for strategy feedback loop
  - `next_provider/2` for explicit fallback handling
  - `get_provider/1` for provider lookup
  - Fallback strategy with failure tracking and thresholds
  - Specialist strategy with keyword detection

- `PortfolioManager.Pipeline` enhancements
  - Parallel step execution with `parallel: true` flag
  - `on_error` policies: `:halt`, `:continue`, `{:retry, count}`
  - `description`, `config`, `metadata` fields on Pipeline struct

- `PortfolioManager.Agent.Tool` enhancements
  - Tool behaviour with callbacks
  - `to_spec/1` for tool specification generation
  - `validate_args/2` for argument validation
  - Context passing (session_id, user_id, repo, router)

### Changed

- Router strategies maintain state for failure tracking

### Dependencies

- No new dependencies required
```

---

## TESTING CHECKLIST

For each task, follow this TDD cycle:
Update or remove legacy tests as needed to match the new API surface.

1. [ ] Write failing test
2. [ ] Implement minimal code to pass
3. [ ] Refactor if needed
4. [ ] Run `mix test` - all pass
5. [ ] Run `mix compile --warnings-as-errors` - no warnings
6. [ ] Run `mix credo --strict` - no issues
7. [ ] Add @doc and @spec
8. [ ] Move to next test

Final validation:
```bash
mix deps.get
mix compile --warnings-as-errors
mix test
mix credo --strict
mix dialyzer
mix docs
```

---

## MOCK SETUP

Ensure test mocks are configured in `/home/home/p/g/n/portfolio_manager/test/support/mocks.ex`:

```elixir
Mox.defmock(PortfolioManager.Mocks.LLM, for: PortfolioCore.Ports.LLM)
```

For Evaluation tests, mock the LLM to return structured evaluation responses.

---

## NOTES

1. **Token estimation**: Use simple heuristic (chars / 4) unless tiktoken dep is acceptable
2. **Parallel execution**: Use `Task.async_stream` with max_concurrency
3. **Error policies**: `:halt` stops pipeline, `:continue` logs and proceeds, `{:retry, n}` retries n times
4. **Keyword detection**: Simple string matching, can be enhanced later with embeddings
5. **Greenfield**: breaking changes are acceptable; remove or rename legacy APIs as needed
