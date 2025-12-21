# Portfolio Manager Examples

Working examples demonstrating Portfolio Manager features using real resources.

## Prerequisites

### Required
- Elixir 1.15+
- A directory with git repositories to scan

### For RAG/AI Features
Set environment variables for LLM providers:

```bash
# Required for embeddings and default LLM
export GOOGLE_API_KEY="your-gemini-api-key"

# Optional additional providers
export ANTHROPIC_API_KEY="your-anthropic-api-key"
export OPENAI_API_KEY="your-openai-api-key"
```

## Quick Start

```bash
# Install dependencies
mix deps.get

# Run all examples
./examples/run_all.sh

# Or run individual examples
mix run examples/01_basic_init.exs
```

## Examples Overview

### Basic Operations

| Example | Description |
|---------|-------------|
| `01_basic_init.exs` | Initialize a portfolio and scan for repos |
| `02_list_and_filter.exs` | List repos with various filters |
| `03_repo_details.exs` | Get detailed repo information |

### Context Management

| Example | Description |
|---------|-------------|
| `04_update_context.exs` | Update repo metadata and context |
| `05_notes_and_decisions.exs` | Add notes and architectural decisions |

### Relationships

| Example | Description |
|---------|-------------|
| `06_relationships.exs` | Create and query repo relationships |
| `14_relationship_graph.exs` | Graph visualization, path finding, cycle detection |

### Search

| Example | Description |
|---------|-------------|
| `07_text_search.exs` | Basic text search across repos |
| `08_semantic_search.exs` | Vector-based semantic search (requires API key) |

### RAG/AI Features

| Example | Description |
|---------|-------------|
| `09_agentic_query.exs` | Ask questions using AI agent with tools |
| `10_chat_session.exs` | Multi-turn conversation with memory |
| `16_agentic_detection.exs` | LLM-powered purpose/type/status detection |

### Editing & Management

| Example | Description |
|---------|-------------|
| `12_edit_and_remove.exs` | Edit repo metadata and remove repos |

### Workflow Engine

| Example | Description |
|---------|-------------|
| `13_workflow_engine.exs` | List, parse, and run YAML-defined workflows |

### Performance & Caching

| Example | Description |
|---------|-------------|
| `15_sqlite_cache.exs` | SQLite-based caching for fast queries |

### Advanced

| Example | Description |
|---------|-------------|
| `11_full_workflow.exs` | Complete workflow: init, scan, enrich, query |

## Running Examples

### Run All Examples

```bash
# Basic examples (no API key required)
./examples/run_all.sh --basic

# All examples including AI features
./examples/run_all.sh --all

# Specific example
mix run examples/01_basic_init.exs
```

### Example Output

Each example prints its progress and results to stdout. Successful runs end with a summary.

## Configuration

Examples use a temporary portfolio at `/tmp/portfolio_manager_examples` by default. Override with:

```bash
export PORTFOLIO_EXAMPLES_PATH="/path/to/portfolio"
```

## Troubleshooting

### "No repos found"
- Ensure you have git repositories in `~/projects` or modify the scan path in the examples

### "API key not set"
- RAG examples require `GOOGLE_API_KEY` at minimum
- Check the Prerequisites section above

### "Connection refused"
- Ensure network access for API calls
- Check firewall settings

## Example Data

Examples will create/use these repos if available:
- Scans `~/projects` and `~/work` directories
- Creates test relationships between discovered repos
- Adds sample notes and decisions

## Cleanup

Remove the example portfolio:

```bash
rm -rf /tmp/portfolio_manager_examples
```
