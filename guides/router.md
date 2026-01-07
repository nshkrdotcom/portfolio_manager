# Router Guide

The Router module provides multi-provider LLM routing with intelligent strategies for selecting the best provider for each request.

## Overview

`PortfolioManager.Router` is a GenServer that manages multiple LLM providers and routes requests based on configurable strategies. It supports:

- **Fallback routing** - Use providers in priority order
- **Round-robin routing** - Distribute requests across healthy providers
- **Specialist routing** - Route by task type and provider capabilities
- **Cost-optimized routing** - Minimize cost while meeting requirements

## Configuration

Configure the router in your manifest file:

```yaml
router:
  strategy: specialist
  health_check_interval: 30000
  providers:
    - name: gemini
      module: PortfolioIndex.Adapters.LLM.Gemini
      config:
        model: gemini-flash-lite-latest
      capabilities:
        - generation
        - code
        - reasoning
      priority: 1

    - name: claude
      module: PortfolioIndex.Adapters.LLM.Anthropic
      config: {}
      capabilities:
        - reasoning
        - analysis
      priority: 2

    - name: openai
      module: PortfolioIndex.Adapters.LLM.OpenAI
      config: {}
      capabilities:
        - generation
        - code
      priority: 3
```

## Basic Usage

### Completing Requests

```elixir
# Use default strategy
{:ok, response} = PortfolioManager.Router.complete([
  %{role: :user, content: "Explain this code"}
])

# Force a specific strategy
{:ok, response} = PortfolioManager.Router.complete(
  [%{role: :user, content: "Analyze this"}],
  strategy: :fallback
)

# Route by task type (for specialist strategy)
{:ok, response} = PortfolioManager.Router.complete(
  [%{role: :user, content: "Fix this bug"}],
  task_type: :code
)
```

### Streaming Responses

```elixir
PortfolioManager.Router.stream(
  [%{role: :user, content: "Write a long explanation"}],
  fn chunk -> IO.write(chunk) end
)
```

## Routing Strategies

### Fallback

Uses the first healthy provider based on priority. Useful for reliability.

```elixir
Router.set_strategy(:fallback)
```

### Round Robin

Distributes requests evenly across healthy providers.

```elixir
Router.set_strategy(:round_robin)
```

### Specialist

Routes requests to providers with matching capabilities for the task type.

```elixir
Router.set_strategy(:specialist)

# Then use task_type when calling
Router.complete(messages, task_type: :code)
Router.complete(messages, task_type: :reasoning)
Router.complete(messages, task_type: :analysis)
```

### Cost Optimized

Routes to the cheapest provider that can handle the request.

```elixir
Router.set_strategy(:cost_optimized)
```

Requires `cost_per_token` to be set on providers.

## Health Checking

The router periodically checks provider health. You can also check manually:

```elixir
Router.health_check(:gemini)  # => :healthy | :unhealthy | :unknown
```

## Managing Providers

### List Providers

```elixir
Router.list_providers()
```

### Register New Provider

```elixir
Router.register_provider(%{
  name: :new_provider,
  module: MyApp.LLM.Custom,
  config: %{api_key: "..."},
  capabilities: [:generation],
  priority: 5
})
```

## Integration with RAG

The RAG module uses the Router for streaming queries:

```elixir
PortfolioManager.RAG.stream_query("How does this work?", fn chunk ->
  IO.write(chunk)
end)
```

## Error Handling

```elixir
case Router.complete(messages) do
  {:ok, response} ->
    IO.puts(response.content)

  {:error, :no_healthy_providers} ->
    IO.puts("All providers are down!")

  {:error, {:provider_error, name, reason}} ->
    IO.puts("Provider #{name} failed: #{inspect(reason)}")
end
```
