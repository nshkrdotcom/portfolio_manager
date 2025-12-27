# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.1] - 2025-12-26

### Added

- Doc ingestion pipeline for repo docs (`docs/**/*.md`) with per-repo index and summaries
- pgvector-backed vector store with Ecto/Postgrex integration and auto schema creation
- `mix portfolio.docs ingest` and `mix portfolio.docs search` CLI tasks for doc indexing and search
- Doc ingestion configuration keys (include/exclude patterns, chunking, embed batch size, delete_existing)
- Developer plan document in `docs/20251225/plan.md`
- Ecto repo registration and migration for the pgvector-backed `rag_chunks` table
- **CLI Tool**: Complete set of 14 mix tasks for portfolio management
  - `mix portfolio.init` - Initialize a new portfolio
  - `mix portfolio.scan` - Discover repositories in directories
  - `mix portfolio.list` - List tracked repositories with filtering
  - `mix portfolio.show` - Show detailed repository information
  - `mix portfolio.add` - Manually add a repository
  - `mix portfolio.remove` - Remove a repository from tracking
  - `mix portfolio.edit` - Edit repository metadata (type, status, tags, notes)
  - `mix portfolio.search` - Search across repositories
  - `mix portfolio.graph` - Visualize relationships
  - `mix portfolio.review` - Review pending agentic detections
  - `mix portfolio.status` - Show portfolio status
  - `mix portfolio.sync` - Sync portfolio state and refresh repo info
  - `mix portfolio.config` - Manage portfolio configuration
  - `mix portfolio.run` - Execute workflows
  - `mix portfolio.ask` - AI-powered natural language queries
  - `mix portfolio.completion` - Generate shell completion scripts (bash/zsh/fish)
  - `mix portfolio.repl` - Interactive REPL mode

- **Workflow Engine**: YAML-defined multi-step automation
  - Git operations (status, fetch, pull, push, commit)
  - Shell command execution
  - LLM/Agent queries
  - File operations (read, write, copy, delete)
  - Context variable interpolation
  - Built-in workflows: port-check, port-sync, health-check, doc-generate, initial-setup

- **Relationship Graph**: Graph operations for repo dependencies
  - Build graph from portfolio relationships
  - ASCII and DOT (Graphviz) visualization
  - Path finding between repos (BFS)
  - Cycle detection
  - Topological sorting
  - Reachability analysis
  - Centrality metrics

- **Agentic Detection**: LLM-powered repository analysis
  - Purpose detection from code analysis
  - Type inference (library, application, port, etc.)
  - Relationship discovery
  - Status assessment
  - Full analysis combining all detection methods
  - Review queue persisted to `.portfolio/reviews/pending.yml`

- **SQLite Cache** (optional): Fast indexed queries for large portfolios
  - Requires optional `exqlite` dependency
  - Full-text search
  - Indexed filtering by language, type, status
  - Relationship caching

- **Shell Completion**: Tab completion for CLI commands
  - Bash completion script
  - Zsh completion script
  - Fish completion script

- **Interactive Mode**: REPL for portfolio exploration
  - Command history
  - Built-in help system
  - All portfolio operations available interactively

- **Enhanced Detection**: Improved repository detection
  - Dependency parsing for Elixir, Python (including setup.py), JavaScript, Rust, and Go
  - Dependency buckets for runtime/dev/optional, including JS peer deps
  - Framework detection (Phoenix, Nerves, FastAPI, Django, React, Next.js, etc.)
  - Git commit statistics (commit count, contributors, first/last commit dates)

- **Computed Views**: Auto-generated aggregated views
  - `views/by-status.yml` - Repos grouped by status
  - `views/by-type.yml` - Repos grouped by type
  - `views/by-language.yml` - Repos grouped by language
  - `views/stale-repos.yml` - Repos with no recent activity
  - `views/port-status.yml` - Port repositories status

- **Markdown Storage**: Notes and decisions persist as markdown files
  - Notes saved to `repos/{id}/notes.md`
  - Decisions saved to `repos/{id}/decisions/{NNN}-{slug}.md`
  - ADR (Architecture Decision Record) format for decisions

- **RAG Integration**: AI-powered features using the RAG library
  - Semantic search with vector embeddings
  - Agentic queries with tool calling
  - Multi-turn chat sessions with memory
  - Multiple LLM provider support (Gemini, Claude, Codex)

- **Agent Tools**: 6 portfolio-specific tools for the agent
  - `search_repos` - Search repositories
  - `get_repo_context` - Get detailed repository context
  - `list_repos` - List repositories with filters
  - `find_relationships` - Find repository relationships
  - `compare_repos` - Compare two repositories
  - `get_portfolio_stats` - Get portfolio statistics

### Changed

- Semantic search now includes per-repo doc summaries in the searchable content
- Default embedding dimensions set to 3072 for Gemini embeddings
- Default config includes doc ingestion and pgvector settings
- Notes now persist to separate markdown files instead of YAML
- Decisions persist to individual markdown files in ADR format
- Default portfolio path now `~/portfolio` (override with `PORTFOLIO_DIR`)
- Workflow YAML schema now uses `schema_version` and `workflow` root keys
- Scan defaults to config directories and exclude patterns; agentic defaults to config
- Sync supports `--full`, `--computed-only`, and `--check-remotes`

### Fixed

- Ensure Req/Ecto dependencies are started before embedding and vector store operations
- Context not being created during repository scan
- RAG provider instantiation (proper struct creation)
- Optional provider support (Claude, Codex) without compile warnings

## [0.1.0] - 2024-12-20

### Added

- Initial release
- Core portfolio management functionality
- YAML-based storage adapter
- Git integration for repository detection
- Basic detection for language and type
- Hexagonal architecture with ports and adapters
- Domain entities: Repo, Context, Relationship, Registry
