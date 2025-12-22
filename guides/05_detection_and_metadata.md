# Detection and Metadata

Deterministic detection inspects known files to infer language, type, framework,
and dependencies. This guide explains what is detected, how it is stored, and
when it is refreshed.

## Deterministic detection sources

Portfolio Manager currently inspects:

- `mix.exs` for Elixir projects.
- `pyproject.toml`, `setup.py`, and `requirements.txt` for Python projects.
- `package.json` for JavaScript/TypeScript projects.
- `Cargo.toml` for Rust projects.
- `go.mod` for Go projects.

It also scans README content for signals (for example, port or fork hints).

## Framework detection

Framework detection is best-effort and language specific:

- Elixir: phoenix, nerves, absinthe, scenic, livebook, ash, commanded.
- Python: django, fastapi, flask, streamlit, gradio.
- JavaScript: next, remix, nuxt, angular, react, vue, svelte, express, fastify, koa.

If no known framework is detected, the framework field is left nil.

## Dependency buckets

Dependencies are normalized into three buckets and stored under
`context.computed.dependencies`:

- `runtime`: required in production.
- `dev`: development or test-only dependencies.
- `optional`: optional or peer dependencies.

Examples:

- Elixir: `optional: true` -> optional, `only: :dev` or `:test` -> dev.
- Python: `project.dependencies` -> runtime, optional groups become dev or optional,
  `install_requires` -> runtime, `tests_require` -> dev, other extras -> optional.
- JavaScript: dependencies -> runtime, devDependencies -> dev,
  peerDependencies/optionalDependencies -> optional.

## Git-derived computed fields

`mix portfolio.sync` computes git stats and stores them in `context.computed`:

- `commit_count_30d`
- `contributors` and `contributor_count`
- `first_commit_date`
- `last_commit` (sha, date, message)
- `last_remote_commit` when `--check-remotes` is used

These fields drive views (stale logic, port status) and filters in the CLI.

## When detection runs

- `mix portfolio.scan` and `mix portfolio.add` run deterministic detection by default.
- `mix portfolio.sync --full` re-runs deterministic detection and queues agentic
  detection for review.
- Use `--no-detect` to skip deterministic detection.

## Overrides

If you need to override fields, use:

```bash
mix portfolio.edit my-app --set status=active
mix portfolio.edit my-app --set computed.commit_count_30d=0
```

Or update context via the Elixir API (`PortfolioManager.update_context/3`).
