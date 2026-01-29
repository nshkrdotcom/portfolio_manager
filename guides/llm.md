# LLM Gateway

The `PortfolioManager.LLM` module is the centralized gateway for all LLM
interactions in Portfolio Manager. Every completion and streaming call flows
through this module, giving you a single integration point for configuration,
observability, and error handling.

## Overview

Rather than calling LLM adapters directly, all modules in Portfolio Manager
(Router, RAG, Evaluation, Agent, eval mix tasks) delegate to `LLM.complete/2`
and `LLM.stream/2`. This gateway:

- Resolves the active LLM adapter from the PortfolioCore registry
- Delegates directly to the configured `PortfolioCore.Ports.LLM` adapter
- Returns responses in the standard port shape (`%{content, usage, model, ...}`)

## Basic Usage

### Completions

```elixir
messages = [
  %{role: :system, content: "You are a helpful code assistant."},
  %{role: :user, content: "Explain pattern matching in Elixir."}
]

{:ok, result} = PortfolioManager.LLM.complete(messages)

IO.puts(result.content)
# => "Pattern matching is a fundamental feature of Elixir..."

IO.inspect(result.usage)
# => %{input_tokens: 24, output_tokens: 150}
```

### Streaming

```elixir
{:ok, stream} = PortfolioManager.LLM.stream(messages)

stream
|> Enum.each(fn chunk ->
  IO.write(chunk)
end)
```

The stream returns an `Enumerable.t()` of content strings, with delta
extraction already applied.

## Options

Both `complete/2` and `stream/2` accept a keyword list of options that are
forwarded to the underlying LLM adapter:

```elixir
PortfolioManager.LLM.complete(messages,
  model: "gemini-1.5-pro-latest",
  max_tokens: 8192,
  temperature: 0.3
)
```

Common options:

| Option | Description | Default |
|--------|-------------|---------|
| `:model` | Override the model name | Adapter default |
| `:max_tokens` | Maximum tokens to generate | Adapter default |
| `:temperature` | Sampling temperature (0.0-2.0) | Adapter default |
| `:stop` | Stop sequences | `nil` |

## Response Format

Successful completions return a normalized map:

```elixir
%{
  content: "The generated text...",
  usage: %{
    input_tokens: 24,
    output_tokens: 150
  },
  model: "gemini-flash-lite-latest",
  finish_reason: :stop,
  response_id: nil
}
```

## How It Connects

The LLM gateway sits between the application modules and the adapter layer:

```
PortfolioManager.RAG ──┐
PortfolioManager.Router ──┤
PortfolioManager.Agent ──┤──> PortfolioManager.LLM
Mix.Tasks.Portfolio.Eval ─┘        │
                                   ▼
                        PortfolioCore.Registry
                        (:llm adapter lookup)
                                   │
                                   ▼
                        PortfolioIndex Adapter
                        (Gemini, OpenAI, Ollama, etc.)
```

## Configuration

The LLM adapter is configured in your manifest:

```yaml
adapters:
  llm:
    adapter: PortfolioIndex.Adapters.LLM.Gemini
    config:
      model: gemini-flash-lite-latest
      max_tokens: 4096
```

The gateway reads the adapter from `PortfolioCore.adapter(:llm)` at call time,
so changing the registered adapter takes effect immediately.

## Error Handling

```elixir
case PortfolioManager.LLM.complete(messages) do
  {:ok, result} ->
    IO.puts(result.content)

  {:error, :rate_limited} ->
    Process.sleep(1000)
    # retry...

  {:error, :timeout} ->
    IO.puts("Request timed out")

  {:error, reason} ->
    IO.puts("LLM error: #{inspect(reason)}")
end
```

## API Reference

### `complete/2`

```elixir
@spec complete([map()], keyword()) :: {:ok, map()} | {:error, term()}
```

Execute a synchronous LLM completion. Messages must be a list of maps with
`:role` and `:content` keys.

### `stream/2`

```elixir
@spec stream([map()], keyword()) :: {:ok, Enumerable.t()} | {:error, term()}
```

Stream an LLM completion. Returns an enumerable of content strings.

## See Also

- [Router Guide](router.md) -- Multi-profile routing on top of the LLM gateway
- [RAG Guide](rag.md) -- How RAG queries use the gateway for answer generation
- [Streaming Guide](streaming.md) -- Streaming patterns and integrations
- [Configuration Guide](configuration.md) -- Manifest-based adapter setup
