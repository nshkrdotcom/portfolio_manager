# Overview and Concepts

Portfolio Manager centralizes project intelligence in a single, versioned portfolio repo.
Everything else (notes, decisions, computed views) hangs off that repo so you can search,
review, and reason about your work without chasing context across dozens of directories.

This guide sets the mental model for the rest of the series.

## The Portfolio Repo

A portfolio is just a git repo with a defined structure. You can keep it alongside your
other work (for example, `~/p/g/n/portfolio`) and point the CLI at it via `PORTFOLIO_DIR`.

Key ideas:

- The portfolio repo is the source of truth for project metadata and notes.
- `.portfolio/` is local-only state (cache, review queue, REPL history) and is gitignored.
- `repos/{id}/` holds per-project context, notes, and decisions.
- `views/` holds computed summaries for human scanning.

## What the Library Does

Portfolio Manager is opinionated but composable. It provides:

- A registry of repositories with structured metadata.
- Per-repo context (notes, decisions, computed fields).
- Detection for language, dependencies, and framework.
- Agentic detection via LLMs with a review queue.
- Graph and views to understand relationships and status.
- Optional SQLite index for fast search and filtering.
- A workflow engine for repeatable multi-step tasks.

## Data Model at a Glance

The core domain types are:

- Repo: identity and canonical metadata.
- Context: repo plus notes, decisions, computed fields.
- Relationship: explicit links between repos.
- Registry: a collection of repos and relationships.

A repo is minimal and stable. Context is where the rich story lives.

## Local State in `.portfolio/`

The `.portfolio/` directory is intentionally local-only:

- `.portfolio/cache/index.db`: SQLite index (optional).
- `.portfolio/reviews/pending.yml`: agentic review queue.
- `.portfolio/state/repl_history`: REPL history file.

You can safely keep these files out of version control while still sharing
all core context in the portfolio repo.

## The Workflow of Use

Most teams follow a rhythm like this:

1. Initialize the portfolio and point it at your working directories.
2. Scan for repos and run deterministic detection.
3. Run agentic detection and review the queue.
4. Sync periodically to refresh computed fields.
5. Use views, graph, search, and workflows to stay oriented.

The next guides walk through each of these steps in depth.
