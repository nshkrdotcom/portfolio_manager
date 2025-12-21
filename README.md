# Portfolio Manager

<p align="center">
  <img src="assets/portfolio_manager.svg" alt="Portfolio Manager Logo" width="200">
</p>

<p align="center">
  <a href="https://hex.pm/packages/portfolio_manager"><img alt="Hex.pm" src="https://img.shields.io/hexpm/v/portfolio_manager.svg"></a>
  <a href="https://hexdocs.pm/portfolio_manager"><img alt="Documentation" src="https://img.shields.io/badge/docs-hexdocs-purple.svg"></a>
  <a href="https://github.com/nshkrdotcom/portfolio_manager/actions"><img alt="Build Status" src="https://img.shields.io/github/actions/workflow/status/nshkrdotcom/portfolio_manager/ci.yml"></a>
  <a href="https://opensource.org/licenses/MIT"><img alt="License" src="https://img.shields.io/hexpm/l/portfolio_manager.svg"></a>
</p>

**AI-native personal project intelligence system - manage, track, and search across all your repositories with semantic understanding and agentic capabilities.**

---

## What Is This?

Portfolio Manager is a pure Elixir library for tracking and managing context about all your software projects. It provides:

- **Registry**: Catalog of all repos you manage across multiple accounts
- **Context**: Structured metadata, notes, and decisions per repo
- **Relationships**: How repos connect (dependencies, ports, forks)
- **Detection**: Auto-detect repo type, language, and purpose
- **Semantic Search**: Vector embeddings via `gemini_ex` for intelligent querying
- **Agentic Queries**: Multi-step reasoning with tool use (search, analyze, compare)
- **Multi-LLM**: Works with Gemini, Codex, and Claude (any combination)
- **Workflows**: Automated tasks (port sync, doc generation, health checks)

All data is stored in a private git repository for versioning and backup.

### RAG Integration

Portfolio Manager integrates with an enhanced RAG system providing:

```
┌─────────────────────────────────────────────────────────────┐
│                    Portfolio Manager                         │
│  semantic_search/3 | query/3 (agentic) | chat/3             │
└─────────────────────────────────────────────────────────────┘
                            │
┌───────────────────────────┴───────────────────────────────┐
│                     RAG Layer                              │
│  Embeddings: gemini_ex    LLMs: gemini/codex/claude       │
│  Search: Torus + pgvector  Agent: Tools + Memory          │
└────────────────────────────────────────────────────────────┘
```

## Installation

Add `portfolio_manager` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:portfolio_manager, "~> 0.1.0"}
  ]
end
```

Then run:

```bash
mix deps.get
```

## Quick Start

### Using the CLI

```bash
# Initialize a portfolio
mix portfolio.init ~/my-portfolio

# Scan directories for repositories
mix portfolio.scan ~/projects ~/work

# List tracked repos
mix portfolio.list
mix portfolio.list --status=active --type=library

# Show repo details
mix portfolio.show my-project

# Add/remove repositories
mix portfolio.add ~/projects/new-repo
mix portfolio.remove old-repo

# Edit repository metadata
mix portfolio.edit my-project --type=library --status=active
mix portfolio.edit my-project --add-tag=elixir --add-tag=ai

# Search across repos
mix portfolio.search authentication

# AI-powered queries (requires GOOGLE_API_KEY)
mix portfolio.ask "which repos use phoenix?"

# Show portfolio status
mix portfolio.status

# Sync portfolio state
mix portfolio.sync
mix portfolio.sync --all --views

# Run workflows
mix portfolio.run --list
mix portfolio.run health-check --repo=my-project
mix portfolio.run port-sync --dry-run

# Configuration management
mix portfolio.config show
mix portfolio.config set sync.auto_commit true
mix portfolio.config add-dir ~/work

# Shell completion (bash/zsh/fish)
mix portfolio.completion --shell=bash >> ~/.bashrc

# Interactive REPL mode
mix portfolio.repl
```

### Using the Elixir API

```elixir
# Initialize with a portfolio repo path
{:ok, portfolio} = PortfolioManager.init("~/portfolio")

# Scan directories for repos
{:ok, discovered} = PortfolioManager.scan(portfolio, ["~/projects", "~/work"])

# List all tracked repos
repos = PortfolioManager.list_repos(portfolio)

# Get detailed context for a repo
{:ok, context} = PortfolioManager.get_context(portfolio, "my-project")

# Search across all repos
results = PortfolioManager.search(portfolio, "authentication")

# Semantic search (requires embeddings)
results = PortfolioManager.semantic_search(portfolio, "error handling patterns")

# Generate computed views
:ok = PortfolioManager.generate_views(portfolio)
```

## Configuration

Portfolio Manager uses a configuration file at the root of your portfolio repo.

### Default Portfolio Location

By default, the portfolio repo is expected at `../portfolio` relative to your working directory. Override this:

```elixir
# In config/config.exs
config :portfolio_manager,
  portfolio_path: "~/my-portfolio",  # Custom path
  auto_sync: true,                   # Auto-commit changes
  embedding_provider: :gemini,       # :gemini | :openai | :none
  embedding_dimensions: 768          # 768 | 1536 | 3072
```

### Environment Variables

```bash
# Required for embeddings
export GOOGLE_API_KEY="your-gemini-api-key"

# Or for OpenAI
export OPENAI_API_KEY="your-openai-key"
```

### Portfolio Config File

The portfolio repo itself contains a `config.yml`:

```yaml
# ~/portfolio/config.yml
version: "1.0"

scan:
  directories:
    - ~/projects
    - ~/work
  exclude:
    - "**/node_modules"
    - "**/.git"

accounts:
  - id: personal
    host: github.com
    username: myuser
  - id: work
    host: github.enterprise.com
    username: work-user

detection:
  agentic: true
  confidence_threshold: 0.85

sync:
  auto_commit: true
  commit_message_prefix: "[portfolio]"
```

## API Reference

### Core Functions

```elixir
# Initialization
PortfolioManager.init(path)           # Initialize/load portfolio
PortfolioManager.init()               # Use default path from config

# Discovery
PortfolioManager.scan(portfolio, dirs) # Scan directories for repos
PortfolioManager.add(portfolio, path)  # Add single repo
PortfolioManager.remove(portfolio, id) # Remove repo from tracking

# Querying
PortfolioManager.list_repos(portfolio, opts \\ [])
PortfolioManager.get_repo(portfolio, id)
PortfolioManager.get_context(portfolio, id)
PortfolioManager.search(portfolio, query, opts \\ [])
PortfolioManager.semantic_search(portfolio, query, opts \\ [])

# Relationships
PortfolioManager.get_relationships(portfolio, id)
PortfolioManager.add_relationship(portfolio, from, to, type)

# Context Management
PortfolioManager.update_context(portfolio, id, updates)
PortfolioManager.add_note(portfolio, id, content)
PortfolioManager.add_decision(portfolio, id, title, content)

# Status
PortfolioManager.status(portfolio)
PortfolioManager.sync(portfolio)
```

### Repo Types

```elixir
:library      # Reusable library/package
:application  # Standalone application
:port         # Port of another library
:fork         # Fork of another repo
:experiment   # Experimental/learning project
:template     # Project template
:config       # Configuration repo
:docs         # Documentation repo
```

### Relationship Types

```elixir
:depends_on   # A depends on B
:port_of      # A is a port of B
:fork_of      # A is a fork of B
:evolved_from # A evolved from B
:related_to   # General relationship
```

## Architecture

Portfolio Manager uses hexagonal architecture:

```
┌─────────────────────────────────────────────────────────────┐
│                        APPLICATION                           │
│  PortfolioManager (main API)                                │
└─────────────────────────────────────────────────────────────┘
                              │
┌─────────────────────────────┴─────────────────────────────┐
│                         DOMAIN                             │
│  Repo | Context | Relationship | Detection | Search       │
└─────────────────────────────────────────────────────────────┘
                              │
┌─────────────────────────────┴─────────────────────────────┐
│                         PORTS                              │
│  StoragePort | GitPort | EmbeddingPort | DetectionPort    │
└─────────────────────────────────────────────────────────────┘
                              │
┌─────────────────────────────┴─────────────────────────────┐
│                        ADAPTERS                            │
│  YAMLStorage | LocalGit | GeminiEmbedding | FileDetector  │
└─────────────────────────────────────────────────────────────┘
```

## Examples

### Track a Port Repository

```elixir
# Add a repo that's a port of an upstream library
{:ok, _} = PortfolioManager.add(portfolio, "~/projects/instructor_ex")

# Set it as a port
PortfolioManager.update_context(portfolio, "instructor_ex", %{
  type: :port,
  port: %{
    upstream_url: "https://github.com/instructor-ai/instructor",
    upstream_language: "python",
    coverage: "partial"
  }
})

# Add relationship
PortfolioManager.add_relationship(
  portfolio,
  "instructor_ex",
  "instructor-ai/instructor",
  :port_of
)
```

### Query by Criteria

```elixir
# Find all active Elixir libraries
PortfolioManager.list_repos(portfolio,
  status: :active,
  type: :library,
  language: :elixir
)

# Find stale repos
PortfolioManager.list_repos(portfolio,
  status: :stale
)

# Find repos by tag
PortfolioManager.list_repos(portfolio,
  tags: ["ai", "ml"]
)
```

### Semantic Search

```elixir
# Search for repos related to a concept
results = PortfolioManager.semantic_search(portfolio,
  "distributed task processing"
)

# Returns ranked results with context
Enum.each(results, fn %{repo_id: id, score: score, snippet: snippet} ->
  IO.puts("#{id} (#{Float.round(score, 2)}): #{snippet}")
end)
```

### Agentic Queries

```elixir
# Ask complex questions - the agent uses tools to find answers
{:ok, result} = PortfolioManager.query(portfolio,
  "Compare my instructor_ex port to the upstream Python version"
)
# Agent: searches repos → gets context → compares → synthesizes answer

IO.puts(result.answer)
# "Key differences between instructor_ex and upstream:
#  1. Uses Ecto for validation instead of Pydantic
#  2. Streaming implementation differs..."

IO.inspect(result.tools_used)
# [:search_repos, :get_repo_context, :find_relationships, :compare_repos]
```

### Interactive Sessions

```elixir
# Multi-turn conversation with memory
{:ok, session} = PortfolioManager.start_session(portfolio)

{:ok, _} = PortfolioManager.chat(session, "Show me all my Elixir libraries")
{:ok, _} = PortfolioManager.chat(session, "Which ones are ports?")
{:ok, _} = PortfolioManager.chat(session, "Tell me more about the second one")
# Session remembers context from previous messages
```

### Workflows

Define automated multi-step tasks in YAML:

```yaml
# ~/.portfolio/workflows/my-workflow.yml
name: my-workflow
description: Custom workflow example
steps:
  - name: check-status
    type: git
    action: status

  - name: run-tests
    type: shell
    command: mix test
    continue_on_error: true

  - name: analyze
    type: agent
    prompt: "Analyze the test results and suggest improvements"
```

Run workflows:

```bash
mix portfolio.run my-workflow --repo=my-project
mix portfolio.run --list  # Show available workflows
```

### Relationship Graph

Visualize repository dependencies:

```elixir
# Build graph from portfolio
graph = PortfolioManager.Graph.build(portfolio)

# ASCII visualization
IO.puts(PortfolioManager.Graph.to_ascii(graph))

# Export to Graphviz DOT format
File.write!("portfolio.dot", PortfolioManager.Graph.to_dot(graph))

# Find path between repos
path = PortfolioManager.Graph.find_path(graph, "app", "core-lib")

# Detect cycles
cycles = PortfolioManager.Graph.find_cycles(graph)

# Topological sort (for build order)
{:ok, order} = PortfolioManager.Graph.topo_sort(graph)
```

### SQLite Cache (Optional)

For large portfolios, enable SQLite caching for faster queries:

```elixir
# Add exqlite to your deps (it's optional)
{:exqlite, "~> 0.23"}

# Start the cache
{:ok, cache} = PortfolioManager.Cache.SQLite.start_link(
  portfolio_path: "~/.portfolio"
)

# Sync repos to cache
PortfolioManager.Cache.SQLite.sync(cache, repos)

# Fast indexed queries
{:ok, results} = PortfolioManager.Cache.SQLite.filter(cache,
  language: "elixir",
  status: :active
)
```

## Development

```bash
# Clone the repo
git clone https://github.com/nshkrdotcom/portfolio_manager
cd portfolio_manager

# Install dependencies
mix deps.get

# Run tests
mix test

# Run with coverage
mix test --cover

# Generate docs
mix docs
```

## Testing

This library uses [Supertester](https://github.com/nshkrdotcom/supertester) for robust OTP testing:

```elixir
# All tests run with async: true
use Supertester.ExUnitFoundation, isolation: :full_isolation

# Deterministic async testing
:ok = cast_and_sync(server, :operation)
assert_genserver_state(server, fn state -> state.count == 1 end)
```

## Related Projects

**Core Infrastructure**:
- [portfolio](https://github.com/nshkrdotcom/portfolio) - Private portfolio data repository (example)
- [rag](https://github.com/nshkrdotcom/rag) - Enhanced RAG library (fork of Bitcrowd)
- [supertester](https://github.com/nshkrdotcom/supertester) - OTP testing toolkit

**LLM Providers** (any combination works):
- [gemini_ex](https://github.com/nshkrdotcom/gemini_ex) - Elixir client for Google Gemini API (embeddings + LLM)
- [codex_sdk](https://github.com/nshkrdotcom/codex_sdk) - OpenAI Codex SDK for Elixir
- [claude_agent_sdk](https://github.com/nshkrdotcom/claude_agent_sdk) - Claude Agent SDK for Elixir

**Search**:
- [Torus](https://github.com/dimamik/torus) - PostgreSQL search integration for Ecto

## License

MIT License - see [LICENSE](LICENSE) for details.

---

<p align="center">
  Built with care by <a href="https://github.com/nshkrdotcom">nshkrdotcom</a>
</p>
