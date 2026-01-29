# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.4.0] - 2026-01-28

### Added

- `PortfolioManager.LLM` - Centralized LLM gateway via `nsai_llm` Actions and Jido.Exec
  - `complete/2` - Execute completions through the configured PortfolioCore LLM adapter
  - `stream/2` - Stream completions through the configured adapter
  - Response and error normalization for consistent return types
- SupertesterCase module with ETS table injection for Registry isolation across async tests
  - `safe_stop/1` helper for graceful GenServer shutdown in tests
- Arcana feature adoption plan and technical roadmap documentation

### Changed

- **Router provider model reworked** - Providers are now lightweight profiles (name, config, capabilities) rather than module references
  - `module` field is now optional (`module() | nil`)
  - Execution delegates to `PortfolioManager.LLM` instead of calling provider modules directly
  - New helpers: `build_llm_opts/2`, `effective_module/1`, `configured_llm_module/0`, `warn_on_mismatched_providers/1`
  - Health check handles nil-module providers
- RAG `generate_answer/3` uses `PortfolioManager.LLM.complete/2` instead of direct adapter calls
- Eval mix tasks (`portfolio.eval.generate`, `portfolio.eval.run`) use `PortfolioManager.LLM.complete/2` instead of `Router.complete/2`
- Manifests switched to profile-based providers (removed per-provider `module:` keys)
  - Development/production manifests use `gemini_fast` and `gemini_reasoning` profiles
  - Test manifest no longer specifies mock module on provider
- Stream responses now use `%{delta: content}` maps instead of plain strings
- Elixir requirement bumped from `~> 1.15` to `~> 1.17`
- Migrated all test files from ExUnit.Case to SupertesterCase with Registry register/clear lifecycle
- Removed sleep-based timing in tests; uses message passing and Process dictionary
- Wrapped expected error logs in `capture_log` to reduce test noise
- Session timestamp monotonicity enforced via `next_timestamp/1` helper
- Agent max iteration log changed from warning to info level
- Moved `preferred_cli_env` to `cli/0` function per Mix 1.15+ convention
- Manifest path resolution searches multiple locations including `app_dir`
- Support pre-configured manifest map in test environment to skip file loading

### Dependencies

- Requires portfolio_core ~> 0.5.0 (VCS port, AgentSession port, backend capabilities, comprehensive guides)
- Requires portfolio_index ~> 0.5.0 (OpenAI Responses API, GPT-5, AgentSession adapters, Git VCS adapter, local LLM with Ollama/vLLM)
- `ex_doc` bumped from `~> 0.31` to `~> 0.40.0`
- `supertester` bumped from `~> 0.5.0` to `~> 0.5.1`
- `codex_sdk` bumped from `0.4.5` to `0.5.0`
- Removed `override: true` from portfolio_core and portfolio_index path deps
- Added `config :jido_action, default_max_retries: 0`
- Added Hammer rate limiter configuration workaround for portfolio_index

### Documentation

- Updated all guides (router, rag, streaming, configuration, getting_started) for profile-based routing and LLM gateway
- Architecture overview rewritten for `PortfolioManager.LLM` execution path
- Router guide documents profile-based provider configuration
- Configuration guide adds Router Profiles section
- Examples README documents `nsai_llm` Actions integration
- Updated example scripts: model references, telemetry handlers, timing tracking

## [0.3.1] - 2025-12-30

### Added

- `mix portfolio.eval.generate` - Generate synthetic evaluation test cases
  - `--sample-size` - Number of chunks to sample (default: 10)
  - `--collection` - Filter chunks by collection
  - `--source-id` - Filter by source document ID
  - Uses LLM to generate realistic questions from chunk content
- `mix portfolio.eval.run` - Run retrieval evaluation
  - `--mode` - Search mode: semantic, fulltext, hybrid (default: semantic)
  - `--collection` - Filter test cases by collection
  - `--generate` - Auto-generate test cases if none exist
  - `--format` - Output format: table, json (default: table)
  - `--fail-under` - Exit with code 1 if recall@5 below threshold (CI integration)
  - Displays Recall@K, Precision@K, MRR, Hit Rate@K metrics
- `mix portfolio.reembed` - Re-embed documents with current embedding model
  - Batch re-embedding with configurable batch size
  - Collection filtering for targeted re-embedding
  - Progress output with `--verbose` flag
  - Dry-run mode for previewing operations
- `mix portfolio.diagnostics` - Show system diagnostics and health
  - Collection, document, and chunk counts
  - Embedding coverage statistics
  - Failed document counts
  - Configuration summary
  - JSON output format support

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
