# Evaluation Guide

Portfolio Manager includes a retrieval evaluation system for measuring and
improving your RAG pipeline's quality. You can generate synthetic test cases,
run retrieval metrics, and evaluate answer quality using the RAG Triad
framework.

## Overview

Evaluation has two sides:

1. **Retrieval evaluation** -- Measure how well your search finds the right
   documents using standard IR metrics (Recall, Precision, MRR, Hit Rate).
2. **Answer evaluation** -- Score generated answers for context relevance,
   groundedness, and answer relevance using LLM-as-judge (the RAG Triad).

## Retrieval Evaluation

### Generating Test Cases

Before you can evaluate retrieval, you need test cases that pair questions with
known-relevant chunks. You can generate these synthetically from your indexed
content:

```bash
# Generate 20 test cases
mix portfolio.eval.generate --sample-size 20

# Generate from a specific collection
mix portfolio.eval.generate --collection my_docs --sample-size 10

# Filter by source document
mix portfolio.eval.generate --source-id doc_abc123
```

Programmatically:

```elixir
alias PortfolioIndex.Evaluation.Generator

{:ok, test_cases} = Generator.generate(repo, sample_size: 20, collection: "my_docs")
```

The generator samples chunks from your index and uses the LLM to create
realistic questions that those chunks should answer.

### Running Evaluations

Run retrieval evaluation against your test cases:

```bash
# Run with default settings (semantic search)
mix portfolio.eval.run

# Use hybrid search mode
mix portfolio.eval.run --mode hybrid

# Auto-generate test cases if none exist
mix portfolio.eval.run --generate --sample-size 10

# CI integration: fail if recall@5 is below 80%
mix portfolio.eval.run --fail-under 0.8

# JSON output for automated processing
mix portfolio.eval.run --format json
```

### Metrics

The evaluation reports four standard IR metrics:

| Metric | Description |
|--------|-------------|
| **Recall@K** | Fraction of relevant chunks found in top K results |
| **Precision@K** | Fraction of top K results that are relevant |
| **MRR** | Mean Reciprocal Rank -- how high is the first relevant result? |
| **Hit Rate@K** | Did at least one relevant chunk appear in top K? |

Example output:

```
Evaluation Results (20 test cases, mode: hybrid)
================================================
Recall@5:     0.850
Precision@5:  0.340
MRR:          0.720
Hit Rate@5:   0.950
```

### Comparing Runs

Track evaluation over time to measure improvements:

```elixir
alias PortfolioIndex.Evaluation

{:ok, runs} = Evaluation.list_runs(repo, limit: 5)
{:ok, comparison} = Evaluation.compare_runs(repo, [run_a.id, run_b.id])
```

## Answer Evaluation (RAG Triad)

The `PortfolioManager.Evaluation` module scores generated answers across three
dimensions, each rated 1-5 with reasoning:

### Context Relevance

Is the retrieved context relevant to the question?

```elixir
{:ok, score} = PortfolioManager.Evaluation.evaluate_context_relevance(generation)
# => {:ok, %{score: 4, reasoning: "The context covers authentication..."}}
```

### Groundedness

Is the answer grounded in (supported by) the provided context?

```elixir
{:ok, score} = PortfolioManager.Evaluation.evaluate_groundedness(generation)
# => {:ok, %{score: 5, reasoning: "All claims are supported..."}}
```

### Answer Relevance

Does the answer actually address the question asked?

```elixir
{:ok, score} = PortfolioManager.Evaluation.evaluate_answer_relevance(generation)
# => {:ok, %{score: 4, reasoning: "The answer addresses the question..."}}
```

### Full Triad Evaluation

Run all three evaluations at once:

```elixir
alias PortfolioManager.Evaluation
alias PortfolioManager.Generation

# Build a generation from a RAG query
generation =
  Generation.new("How does auth work?")
  |> Generation.with_context(context_string, source_refs)
  |> Generation.with_response(llm_answer)

{:ok, triad} = Evaluation.evaluate_rag_triad(generation)

IO.inspect(triad)
# => %{
#   context_relevance: %{score: 4, reasoning: "..."},
#   groundedness: %{score: 5, reasoning: "..."},
#   answer_relevance: %{score: 4, reasoning: "..."},
#   overall: 4.33
# }
```

### Hallucination Detection

Detect unsupported claims in a generated answer:

```elixir
{:ok, result} = Evaluation.detect_hallucination(generation)

IO.inspect(result)
# => %{
#   has_hallucination: false,
#   unsupported_claims: [],
#   evidence: "All statements are supported by the provided context."
# }
```

## The Generation Struct

`PortfolioManager.Generation` tracks the full RAG lifecycle as a struct that
flows through evaluation:

```elixir
generation =
  Generation.new("What is the caching strategy?")
  |> Generation.with_embedding(query_embedding)
  |> Generation.with_retrieval(search_results)
  |> Generation.with_context(formatted_context, source_refs)
  |> Generation.with_prompt(final_prompt)
  |> Generation.with_response(llm_response)
  |> Generation.with_evaluation(:rag_triad, triad_result)

Generation.success?(generation)
# => true
```

## CI Integration

Use evaluation in your CI pipeline to catch retrieval regressions:

```bash
# In your CI script
mix portfolio.eval.run --fail-under 0.8 --format json

# Exit code 1 if recall@5 drops below 0.8
```

Combine with `--generate` for bootstrapping:

```bash
mix portfolio.eval.run --generate --sample-size 50 --fail-under 0.7
```

## Telemetry

Evaluation operations emit telemetry events:

```elixir
[:portfolio_manager, :evaluation, :rag_triad]
[:portfolio_manager, :evaluation, :hallucination]
```

Measurements include `duration_ms` and individual dimension scores.

## See Also

- [RAG Guide](rag.md) -- Building queries that feed into evaluation
- [Configuration Guide](configuration.md) -- Manifest settings for RAG strategies
- [CLI Reference](cli.md) -- Full eval task options
