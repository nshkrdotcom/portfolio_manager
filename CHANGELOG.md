# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.3.0] - 2025-12-28

### Breaking

- `PortfolioManager.Agent.Session.new/0` replaced by `new/1` (context/metadata supported; message schema normalized)
- `PortfolioManager.Agent.run/2` replaced by session-based `process/3` and `process_with_tools/4`
- `PortfolioManager.Router.complete/2` replaced by `execute/2` and `execute_with_retry/2`
- Tool definitions now support `PortfolioManager.Agent.Tool` behaviour modules

### Added

- `PortfolioManager.Router` - Multi-provider LLM routing
  - Strategies: fallback, round_robin, specialist, cost_optimized
  - Health checking with configurable intervals
  - Streaming support
  - Supports Gemini, Anthropic (via claude_agent_sdk), OpenAI (via codex_sdk)
  - `route/2` exposes provider selection
  - `execute/2` for route + execute in one call
  - `execute_with_retry/2` for retry/fallback execution
  - `report_result/3` for strategy feedback loop
  - `next_provider/2` for explicit fallback handling
  - `get_provider/1` for provider lookup
  - `unregister_provider/1` for removing providers
  - Fallback strategy with failure tracking and thresholds
  - Specialist strategy with keyword detection

- `PortfolioManager.RAG.stream_query/3` - Stream RAG responses
- `PortfolioManager.RAG.stream_search/3` - Stream search results

- `PortfolioManager.Agent` - Tool-using agent framework
  - Built-in tools: search_code, read_file, list_files, get_graph_context
  - Configurable max iterations
  - Session management
  - `process/3` for session-based LLM interaction without tools
  - `process_with_tools/4` for agentic tool loops
  - `with_context/3` for context injection across iterations
  - Improved tool call parsing with nested JSON support

- `PortfolioManager.Agent.Session` enhancements
  - `context`, `metadata`, `tool_results`, `updated_at` fields for session state
  - `add_tool_result/3` for structured tool results
  - `to_llm_messages/1` for LLM-ready message formatting
  - `token_estimate/1` for rough token counting
  - `last_messages/2` for conversation windowing
  - `clear_messages/1` preserving context and tool results
  - `with_context/3` and `get_context/2` for context management

- `PortfolioManager.Agent.Tool` enhancements
  - Tool behaviour with `@callback` definitions
  - `to_spec/1` and `to_spec/2` for tool specification generation
  - `validate_args/2` for argument validation
  - `format_for_llm/1` for LLM prompt formatting
  - `default_context/0` and `context_from_session/1` for context management

- `PortfolioManager.Pipeline` - DAG-based workflow orchestration
  - Dependency resolution
  - Step caching
  - Timeout handling
  - Telemetry events
  - Parallel step execution with `parallel: true` flag
  - `on_error` policies: `:halt`, `:continue`, `{:retry, count}`
  - `description`, `config`, `metadata` fields on Pipeline struct
  - `new/2` and `add_step/4` for programmatic pipeline construction

- `PortfolioManager.Evaluation` - RAG quality evaluation
  - `evaluate_rag_triad/2` - Context relevance, groundedness, answer relevance (1-5 scores with reasoning + overall)
  - `detect_hallucination/2` - Hallucination detection with evidence
  - Telemetry events for evaluation metrics

- `PortfolioManager.Generation` - Unified RAG state container
  - Tracks full lifecycle: query -> embedding -> retrieval -> context -> prompt -> response -> evaluation
  - Builder functions: `with_embedding/2`, `with_retrieval/2`, `with_context/3`, etc.
  - Error tracking and halt support

- CLI `--stream` flag for `mix portfolio.ask`
- Manifest configuration for router, agent, and pipelines
- New guides: router.md, agent.md, pipeline.md, streaming.md
- New examples: router_usage.exs, streaming_query.exs, agent_task.exs, pipeline_workflow.exs

### Changed

- Updated dependency on portfolio_core to ~> 0.2.0
- Updated dependency on portfolio_index to ~> 0.2.0
- Application now starts Router GenServer
- Router strategies maintain state for failure tracking
- Session messages now include timestamps and normalized structure

### Dependencies

- Requires portfolio_core ~> 0.2.0
- Requires portfolio_index ~> 0.2.0 (includes claude_agent_sdk and codex_sdk adapters)

## [0.2.0] - 2025-12-27

### Added

- Manifest-driven configuration (`config/manifests/*`)
- Refactored application supervision around the manifest engine
- RAG interface delegating to portfolio_index strategies
- Graph interface and CLI tasks for ask/search/index/graph
- New runnable examples for RAG, indexing, graph analysis, and workflows
- Mox-based tests for RAG, graph, and CLI tasks
- New documentation guides: Getting Started, RAG, Graph, Configuration, CLI Reference
- ExDoc configuration for publishing guides with module grouping

### Fixed

- Manifest schema now accepts `rag` configuration, Neo4j/Boltx is configured via environment defaults, default manifests use Gemini adapters, pgvector types are wired for the index repo, index creation now normalizes string config, and ingestion uses the requested index ID with dimension mismatch detection

### Changed

- Rebuilt the examples set, refreshed the runner, and clarified setup guidance for RAG/graph demos
- Updated dependencies to use portfolio_core and portfolio_index split
- README refreshed for new architecture and CLI usage

### Removed

- Outdated guides that documented the pre-0.2.0 architecture (portfolio repo structure, workflow engine, agentic detection, SQLite cache, shell completion)

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
