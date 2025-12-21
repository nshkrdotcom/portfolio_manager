# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- **CLI Tool**: Mix tasks for portfolio management
  - `mix portfolio.init` - Initialize a new portfolio
  - `mix portfolio.scan` - Discover repositories in directories
  - `mix portfolio.list` - List tracked repositories with filtering
  - `mix portfolio.show` - Show detailed repository information
  - `mix portfolio.add` - Manually add a repository
  - `mix portfolio.search` - Search across repositories
  - `mix portfolio.status` - Show portfolio status
  - `mix portfolio.ask` - AI-powered natural language queries

- **Enhanced Detection**: Improved repository detection
  - Dependency parsing for Elixir, Python, JavaScript, Rust, and Go
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

- Notes now persist to separate markdown files instead of YAML
- Decisions persist to individual markdown files in ADR format
- Enhanced Python dependency detection to support pyproject.toml

### Fixed

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
