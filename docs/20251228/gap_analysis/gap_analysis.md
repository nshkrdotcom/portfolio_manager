# Portfolio Manager Gap Analysis: rag_ex Feature Comparison

**Date:** 2025-12-28
**Current Version:** 0.3.0
**Target Version:** 0.4.0

## Executive Summary

This document compares `portfolio_manager` against `rag_ex`'s high-level feature inventory to identify gaps and enhancement opportunities. The analysis focuses on Agent, Router, Pipeline, and Evaluation modules.

## Assumptions

- **Greenfield release**: v0.4.0 does not need to preserve legacy APIs. Breaking changes are acceptable.
- **Port alignment first**: Prefer matching `portfolio_core` port contracts even if it requires renaming or removing existing functions.

---

## 1. Agent Framework Comparison

### 1.1 Session (rag_ex: `Rag.Agent.Agent`)

| Feature | rag_ex | portfolio_manager | Status |
|---------|--------|-------------------|--------|
| UUID-based session ID | Yes | Yes (hex string) | PRESENT |
| created_at timestamp | Yes | Yes | PRESENT |
| messages list | Yes (structured) | Yes (loose maps) | NEEDS ENHANCEMENT |
| context map | Yes | No | MISSING |
| metadata map | Yes | No | MISSING |
| Message format (role, content, timestamp, tool_name, error) | Yes | No (minimal) | NEEDS ENHANCEMENT |
| `add_message/2` | Yes | Yes | PRESENT |
| `add_tool_result/2` | Yes | No | MISSING |
| `to_llm_messages/1` | Yes | No (manual) | MISSING |
| `token_estimate/1` | Yes | No | MISSING |
| `message_count/1` | Yes | No (trivial) | MISSING |
| `last_messages/2` | Yes | No | MISSING |
| `clear_messages/1` (keeps context) | Yes | No | MISSING |

**Gap Summary:** Session lacks context, metadata, structured messages, and helper functions.

### 1.2 Agent Core (rag_ex: `Rag.Agent.Agent`)

| Feature | rag_ex | portfolio_manager | Status |
|---------|--------|-------------------|--------|
| Tool registry with register/execute/list | Yes | Partial (hardcoded list_all) | NEEDS ENHANCEMENT |
| `format_for_llm/1` | Yes | Yes (manual in format_tools) | PRESENT |
| `process/3` for session-based LLM interaction | Yes | No (only run/2) | MISSING |
| `process_with_tools/4` for agentic loop | Yes | Yes (run/2) | PRESENT |
| `parse_tool_call/1` for JSON detection | Yes | Partial (parse_response) | NEEDS ENHANCEMENT |
| `with_context/2` for context injection | Yes | No | MISSING |

**Gap Summary:** Needs `process/3`, `process_with_tools/4`, improved tool registry, `with_context/2`.

### 1.3 Tool System (rag_ex: `Rag.Agent.Tool`)

| Feature | rag_ex | portfolio_manager | Status |
|---------|--------|-------------------|--------|
| Behaviour callbacks: name(), description(), parameters() | Yes | No (map-based) | NEEDS ENHANCEMENT |
| `execute(args, context)` callback | Yes | Partial (no context) | NEEDS ENHANCEMENT |
| `to_spec/1` helper | Yes | No | MISSING |
| `validate_args/2` helper | Yes | No | MISSING |
| `format_for_llm/1` helper | Yes | Partial (inline) | PRESENT |
| Context with session_id, user_id, repo, router | Yes | No | MISSING |

**Gap Summary:** Needs behaviour-based tools with context, validation helpers.

---

## 2. Router Comparison

### 2.1 Core Router (rag_ex: `Rag.Router`)

| Feature | rag_ex | portfolio_manager | Status |
|---------|--------|-------------------|--------|
| `new/1` with providers, strategy, auto_detect, fallback_order | Yes | Yes (init) | PRESENT |
| `route/2` returns selected provider | Yes | Partial (internal) | NEEDS ENHANCEMENT |
| `execute/2` selects and executes in one call | Yes | Partial (complete/2) | NEEDS ENHANCEMENT |
| `execute_with_retry/2` retries on failure | Yes | No | MISSING |
| `report_result/3` updates strategy state | Yes | No | MISSING |
| `next_provider/2` for fallback | Yes | No (implicit) | MISSING |
| `available_providers/1` | Yes | Yes (list_providers) | PRESENT |
| `get_provider/1` | Yes | Partial | NEEDS ENHANCEMENT |

**Gap Summary:** Needs `route/2`, `execute/2`, `execute_with_retry/2`, `report_result/3`, `next_provider/2`.

### 2.2 Routing Strategies (rag_ex)

| Strategy | rag_ex | portfolio_manager | Status |
|----------|--------|-------------------|--------|
| Fallback with failure tracking | Yes (state) | Partial (no tracking) | NEEDS ENHANCEMENT |
| RoundRobin with load distribution | Yes | Yes | PRESENT |
| Specialist with keyword detection | Yes | Partial (no keywords) | NEEDS ENHANCEMENT |
| Cost Optimized | Custom | Yes | PRESENT |
| Auto-detect strategy | Yes | No | MISSING |

**Gap Summary:** Strategies need state tracking, failure counting, keyword detection.

---

## 3. Pipeline Comparison

### 3.1 Pipeline Core (rag_ex: `Rag.Pipeline`)

| Feature | rag_ex | portfolio_manager | Status |
|---------|--------|-------------------|--------|
| Pipeline struct (name, description, steps, config, metadata) | Yes | Partial (no description, config, metadata) | NEEDS ENHANCEMENT |
| Step struct with parallel flag | Yes | No | MISSING |
| Step on_error policy | Yes | No (halt only) | MISSING |
| Step cache flag | Yes | Yes | PRESENT |
| Step timeout | Yes | Yes | PRESENT |
| Context struct (query, embedding, results, etc.) | Yes | Partial (simple map) | NEEDS ENHANCEMENT |
| Executor with ETS caching | Yes | Yes | PRESENT |
| Parallel execution | Yes | No | MISSING |
| Telemetry events | Yes | Yes | PRESENT |

**Gap Summary:** Needs parallel execution, on_error policies, enriched structs.

---

## 4. Evaluation Module (rag_ex: `Rag.Evaluation`)

| Feature | rag_ex | portfolio_manager | Status |
|---------|--------|-------------------|--------|
| `evaluate_rag_triad/2` | Yes | No | MISSING |
| context_relevance scoring (1-5) | Yes | No | MISSING |
| groundedness scoring (1-5) | Yes | No | MISSING |
| answer_relevance scoring (1-5) | Yes | No | MISSING |
| Scores with reasoning | Yes | No | MISSING |
| `detect_hallucination/2` | Yes | No | MISSING |
| Telemetry integration | Yes | No | MISSING |

**Gap Summary:** Entire module is missing. Needs complete implementation.

---

## 5. Generation Struct (rag_ex: `Rag.Generation`)

| Feature | rag_ex | portfolio_manager | Status |
|---------|--------|-------------------|--------|
| query field | Yes | No | MISSING |
| query_embedding field | Yes | No | MISSING |
| retrieval_results field | Yes | No | MISSING |
| context field | Yes | No | MISSING |
| context_sources field | Yes | No | MISSING |
| prompt field | Yes | No | MISSING |
| response field | Yes | No | MISSING |
| evaluations field | Yes | No | MISSING |
| halted? flag | Yes | No | MISSING |
| errors list | Yes | No | MISSING |

**Gap Summary:** Entire struct is missing. Needs complete implementation.

---

## 6. Priority Implementation List

### High Priority (P1) - Core Functionality Gaps

1. **Evaluation Module** - Critical for RAG quality
   - `PortfolioManager.Evaluation`
   - `evaluate_rag_triad/2`
   - `detect_hallucination/2`

2. **Generation Struct** - Unified RAG state container
   - `PortfolioManager.Generation`
   - All fields from rag_ex

3. **Session Enhancements**
   - Add context, metadata fields
   - Add `token_estimate/1`, `last_messages/2`, `clear_messages/1`
   - Structured message format with timestamps

### Medium Priority (P2) - Enhancement Gaps

4. **Agent Enhancements**
   - Add `process/3` for session-based LLM calls
   - Add `process_with_tools/4` for agentic loop
   - Add `with_context/2` for context injection
   - Improve tool call parsing (nested JSON)

5. **Router Enhancements**
   - Add `route/2` (expose provider selection)
   - Add `execute/2` (unified interface)
   - Add `execute_with_retry/2` (retry on provider failure)
   - Add `report_result/3` (feedback loop)
   - Add `next_provider/2` (explicit fallback)

6. **Strategy Enhancements**
   - Fallback: failure tracking with configurable thresholds
   - Specialist: keyword detection mapping

### Lower Priority (P3) - Pipeline Enhancements

7. **Pipeline Enhancements**
   - Parallel step execution
   - on_error policies (halt, continue, retry)
   - Enriched Pipeline/Step structs

8. **Tool System Enhancements**
   - Tool behaviour module
   - `validate_args/2`
   - Context passing to tools

---

## 7. Files Requiring Changes

### New Files to Create

```
lib/portfolio_manager/evaluation.ex          # P1
lib/portfolio_manager/generation.ex          # P1
```

### Files to Modify

```
lib/portfolio_manager/agent/session.ex       # P1/P2
lib/portfolio_manager/agent.ex               # P2
lib/portfolio_manager/agent/tool.ex          # P3
lib/portfolio_manager/router.ex              # P2
lib/portfolio_manager/pipeline.ex            # P3
```

### New Test Files

```
test/evaluation_test.exs                     # P1
test/generation_test.exs                     # P1
test/agent/session_test.exs                  # P1
```

---

## 8. Estimated Effort

| Component | New LOC | Modified LOC | Tests LOC | Total |
|-----------|---------|--------------|-----------|-------|
| Evaluation | ~150 | 0 | ~100 | ~250 |
| Generation | ~100 | 0 | ~80 | ~180 |
| Session Enhancement | ~50 | ~30 | ~100 | ~180 |
| Agent Enhancement | ~80 | ~40 | ~60 | ~180 |
| Router Enhancement | ~100 | ~60 | ~80 | ~240 |
| Pipeline Enhancement | ~80 | ~50 | ~60 | ~190 |
| **Total** | **~560** | **~180** | **~480** | **~1220** |

---

## 9. Dependencies and Constraints

1. **Evaluation requires LLM adapter** - Will use Router for LLM calls
2. **Generation struct is passive** - No external dependencies
3. **Token estimation** - May need tiktoken-like library or rough estimation
4. **Parallel execution** - Uses Task.async_stream, no new deps
5. **No compatibility constraints** - Legacy APIs can be removed if they conflict with port parity

---

## 10. Success Criteria

- [ ] All updated tests pass (legacy-only tests removed or rewritten)
- [ ] No compiler warnings
- [ ] No dialyzer errors
- [ ] No credo issues (--strict)
- [ ] New modules have >80% test coverage
- [ ] Documentation for all public functions
- [ ] CHANGELOG updated for v0.4.0
- [ ] Version bumped in mix.exs and README.md
