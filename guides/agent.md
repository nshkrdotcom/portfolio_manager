# Agent Guide

The Agent module provides a tool-using framework for complex code analysis tasks that require multiple steps.

## Overview

`PortfolioManager.Agent` enables LLM-powered agents that can iteratively use tools to gather information and solve problems. The agent:

1. Receives a task description
2. Decides which tools to use
3. Executes tools and collects results
4. Iterates until it has enough information
5. Returns a final answer

## Basic Usage

```elixir
{:ok, answer} = PortfolioManager.Agent.run(
  "Find all usages of the GenServer module and suggest improvements",
  tools: [:search_code, :read_file, :get_graph_context]
)
```

## Available Tools

### search_code

Search the codebase using semantic similarity.

```elixir
# Parameters:
# - query (required): Search query string
# - limit (optional): Maximum results, default 5
```

### read_file

Read contents of a file from the repository.

```elixir
# Parameters:
# - path (required): File path to read
# - start_line (optional): Starting line number
# - end_line (optional): Ending line number
```

### list_files

List files in a directory matching a pattern.

```elixir
# Parameters:
# - path (required): Directory path
# - pattern (optional): Glob pattern, default "*"
```

### get_graph_context

Get related entities from the knowledge graph.

```elixir
# Parameters:
# - entity (required): Entity name to find context for
# - depth (optional): Traversal depth, default 2
```

## Configuration

Configure agent settings in your manifest:

```yaml
agent:
  max_iterations: 10
  timeout: 300000
  tools:
    - search_code
    - read_file
    - list_files
    - get_graph_context
```

## Options

```elixir
PortfolioManager.Agent.run("Task description",
  tools: [:search_code, :read_file],  # Limit available tools
  max_iterations: 5                   # Limit iterations
)
```

## How It Works

1. **Prompt Construction**: The agent builds a prompt that includes:
   - The task description
   - Available tools with their descriptions
   - Previous tool calls and results (memory)

2. **Tool Selection**: The LLM responds with either:
   - A tool call: `{"tool": "search_code", "args": {"query": "GenServer"}}`
   - A final answer: `{"answer": "Based on my analysis..."}`

3. **Tool Execution**: When a tool is called, the agent:
   - Executes the tool with provided arguments
   - Stores the result in memory
   - Continues to the next iteration

4. **Termination**: The agent stops when:
   - It provides a final answer
   - Maximum iterations are reached
   - An error occurs

## Example: Code Analysis

```elixir
{:ok, analysis} = PortfolioManager.Agent.run("""
Analyze the authentication system in this codebase:
1. Find the main authentication modules
2. Identify security patterns being used
3. Suggest any improvements
""", tools: [:search_code, :read_file])

IO.puts(analysis)
```

## Listing Available Tools

```elixir
PortfolioManager.Agent.available_tools()
# => [:search_code, :read_file, :list_files, :get_graph_context]
```

## Error Handling

```elixir
case PortfolioManager.Agent.run("Task") do
  {:ok, answer} ->
    IO.puts(answer)

  {:error, :no_progress} ->
    IO.puts("Agent could not make progress")

  {:error, reason} ->
    IO.puts("Error: #{inspect(reason)}")
end
```

## Sessions

Each agent run creates a new session with a unique ID. The session tracks:
- Creation timestamp
- Messages exchanged
- Tools called and their results

## Best Practices

1. **Be Specific**: Provide clear, specific task descriptions
2. **Limit Tools**: Only enable tools needed for the task
3. **Set Reasonable Limits**: Adjust max_iterations based on task complexity
4. **Handle Errors**: Always handle potential error cases
