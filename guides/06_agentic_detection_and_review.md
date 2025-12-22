# Agentic Detection and Review

Agentic detection uses LLMs to infer purpose, type, status, and relationships
when deterministic signals are not enough. All agentic outputs go through a
review queue before they are applied to the portfolio.

## Run agentic detection

CLI:

```bash
mix portfolio.scan --agentic
mix portfolio.scan --agentic --review
mix portfolio.sync --full
```

API:

```elixir
{:ok, result} = PortfolioManager.Detection.Agentic.analyze_with_review(
  repo_path,
  portfolio,
  repo_id: "my-app",
  auto_accept_threshold: 0.9
)
```

## Review queue

Pending review items are stored locally at:

```
.portfolio/reviews/pending.yml
```

Each item includes:

- `repo_id`
- `field` (purpose, type, status, relationship)
- `value`
- `confidence`
- `reasoning` (when available)

## Review workflow

Interactive review:

```bash
mix portfolio.review
mix portfolio.review my-app
```

Bulk accept by confidence:

```bash
mix portfolio.review --accept-all --threshold=0.9
```

Accepted items are applied to repo context and persisted on sync.
Rejected or skipped items remain in the queue.

## Provider routing

Agentic detection routes through the RAG router and supports multiple providers.
To prefer a provider, pass a `provider` option in API calls or use `--provider`
with `mix portfolio.ask`.

Tip: keep `.portfolio/reviews` local so only reviewed changes land in git.
