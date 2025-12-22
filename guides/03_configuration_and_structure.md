# Configuration and Portfolio Structure

This guide explains how the portfolio repo is laid out, what each file holds, and
how to configure scanning, agentic detection, and sync behavior.

## Portfolio layout

A portfolio is a single git repo. It contains all metadata and documentation about
all your projects. Individual repositories stay clean; the portfolio repo is the
source of truth.

```
portfolio/
|-- config.yml
|-- registry.yml
|-- relationships.yml
|-- repos/
|   `-- repo-id/
|       |-- context.yml
|       |-- notes.md
|       `-- decisions/
|           `-- 001-adr-title.md
`-- views/
    |-- by-status.yml
    |-- by-type.yml
    |-- by-language.yml
    |-- stale-repos.yml
    `-- port-status.yml
```

Local-only state lives in `.portfolio/` and is gitignored:

```
.portfolio/
|-- cache/index.db
|-- reviews/pending.yml
`-- state/repl_history
```

Use `PORTFOLIO_DIR` or `mix portfolio.init` to point the CLI at the correct
portfolio location.

## config.yml

`config.yml` controls scanning and defaults. Example:

```yaml
version: "1.0"

scan:
  directories:
    - ~/p/g/n
    - ~/p/g/other
  exclude_patterns:
    - "**/node_modules/**"
    - "**/.git/**"
    - "**/deps/**"
    - "**/_build/**"

agents:
  enabled: true
  auto_detect: true

sync:
  auto_commit: false
```

Notes:
- `agents.enabled` and `agents.auto_detect` are optional; when true, scan can
  default to agentic detection.
- `sync.auto_commit` is reserved for external automation (the CLI does not
  auto-commit).

Use `mix portfolio.config` to view or update config values.

## registry.yml and relationships.yml

- `registry.yml` holds the canonical list of repos and core metadata.
- `relationships.yml` tracks edges between repos (depends_on, port_of, fork_of, etc).

These files are written by the CLI and API; treat them as source data.

## Per-repo context

Each repo has a folder under `repos/{id}/` with rich context:

- `context.yml`: structured metadata and computed fields.
- `notes.md`: free-form notes.
- `decisions/*.md`: ADR-style decisions (one file per decision).

A minimal `context.yml` looks like:

```yaml
repo:
  id: my-app
  name: my-app
  type: application
  status: active
  language: elixir
  tags:
    - core

computed:
  commit_count_30d: 12
  contributor_count: 3
```

## Repo IDs and naming

Repo IDs default to the directory basename. Override them at add time:

```bash
mix portfolio.add ~/projects/my-app --id=my-app-core
```

Keep IDs stable because they anchor notes, decisions, and relationships.
