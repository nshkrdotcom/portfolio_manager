# Operations and Migration

This guide covers operational routines, centralized repo practices, and how to
migrate legacy repo metadata into the portfolio.

## Centralized portfolio model

All structured metadata lives in the portfolio repo (for example
`~/p/g/n/portfolio`). Individual repositories should remain clean and unchanged.
Local runtime state lives in `.portfolio/` and should not be committed.

Recommended setup:

```bash
export PORTFOLIO_DIR=~/p/g/n/portfolio
mix portfolio.init
```

## Operational cadence

A typical workflow for staying up to date:

1. `mix portfolio.scan` to discover repos.
2. `mix portfolio.scan --agentic --review` to capture intent and relationships.
3. `mix portfolio.sync` to refresh computed fields.
4. `mix portfolio.sync --views` to regenerate views when needed.
5. Commit and push changes in the portfolio repo.

## Migration strategy

When migrating legacy repo docs into the portfolio:

- Map docs into `repos/{id}/notes.md` and `repos/{id}/decisions/*.md`.
- Keep decision records in ADR format for durable context.
- Use `mix portfolio.add` or `mix portfolio.scan` to establish registry entries
  before importing notes.

Suggested steps:

1. Inventory existing docs across repos and classify by type (notes, ADRs, specs).
2. Define a mapping from legacy docs to portfolio context fields.
3. Run an ingestion script in dry-run mode, review diffs, then apply.
4. Verify counts and samples, then remove duplicated docs from the repos.

## Cleanup and drift control

- Treat the portfolio repo as the single source of truth.
- Keep `.portfolio/` local; it can be regenerated on any machine.
- Re-run sync and regenerate views after major migrations.

## Multi-machine setup

- Use git to sync the portfolio repo across machines.
- Ignore `.portfolio/` in git so local cache and review queues do not conflict.
