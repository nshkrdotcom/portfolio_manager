# CLI Reference

Portfolio Manager exposes its CLI as Mix tasks: `mix portfolio.<command>`.

## Common flags

- `--help` shows command help.
- `--json` emits machine-readable output (supported by most commands).
- `--portfolio-dir`, `-d` overrides the portfolio root (supported by most commands).

## Initialize and configure

- `mix portfolio.init [path]`
  Initialize a portfolio repo (defaults to `~/portfolio` or `PORTFOLIO_DIR`).

- `mix portfolio.config show|get|set|list-dirs|add-dir|remove-dir`
  Manage `config.yml` values and scan directories.

## Discover and register repos

- `mix portfolio.scan [dirs...]`
  Discover repos from directories.
  Key options: `--dry-run`, `--no-detect`, `--agentic`, `--review`, `--no-agentic`.

- `mix portfolio.add <path>`
  Add a single repo.
  Key options: `--id`, `--type`, `--status`, `--detect`, `--no-detect`.

- `mix portfolio.remove <id>`
  Remove a repo from tracking.
  Key options: `--force`, `--keep-docs`.

- `mix portfolio.edit <id> [field]`
  Edit context or open an editor.
  Key options: `--set key=value`, `--note`, `--decision`, `--type`, `--status`.

## Browse and report

- `mix portfolio.list`
  List repos with filters.
  Key options: `--status`, `--type`, `--language`, `--tag`, `--sort`, `--limit`, `--format`.

- `mix portfolio.show <id>`
  Show detailed context.
  Key options: `--section=notes|decisions|todos|port`, `--related`.

- `mix portfolio.status`
  Portfolio-level summary.

- `mix portfolio.sync [id]`
  Refresh computed fields and metadata.
  Key options: `--full`, `--computed-only`, `--check-remotes`, `--views`.

## Search and ask

- `mix portfolio.search <query>`
  Text search across repo metadata.
  Key options: `--field`, `--regex`, `--case-sensitive`.

- `mix portfolio.ask <question>`
  Agentic query with tools (requires API keys).
  Key options: `--provider`.

## Graphs and reviews

- `mix portfolio.graph [id]`
  Render the relationship graph.
  Key options: `--depth`, `--type`, `--output`, `--ascii`.

- `mix portfolio.review [id]`
  Review pending agentic detections.
  Key options: `--accept-all`, `--threshold`.

## Workflows

- `mix portfolio.run --list`
  List built-in and user workflows.

- `mix portfolio.run <workflow> --repo <id>`
  Run a workflow on a repo.
  Key options: `--dry-run`, `--verbose`.

## Shell integration

- `mix portfolio.completion bash|zsh|fish`
  Generate shell completion scripts.

- `mix portfolio.repl`
  Interactive REPL with command history stored in `.portfolio/state/repl_history`.
