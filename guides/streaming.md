# Streaming Guide

Portfolio Manager supports streaming responses for LLM queries, providing a better user experience for long responses.

## Overview

Streaming allows you to receive LLM responses incrementally as they are generated, rather than waiting for the complete response. This is useful for:

- **Better UX** - Show progress as text is generated
- **Lower latency** - Start displaying content immediately
- **Real-time applications** - Process tokens as they arrive

## RAG Streaming

### stream_query/3

Stream a RAG query with context retrieval:

```elixir
PortfolioManager.RAG.stream_query(
  "How does the authentication system work?",
  fn chunk -> IO.write(chunk) end,
  strategy: :hybrid,
  top_k: 5
)
```

The callback receives each chunk of the response as it's generated.

### stream_search/3

Stream search results as they're found:

```elixir
PortfolioManager.RAG.stream_search(
  "GenServer pattern",
  fn result -> IO.inspect(result) end,
  limit: 10
)
```

## Router Streaming

Use the Router directly for streaming:

```elixir
messages = [
  %{role: :system, content: "You are a helpful assistant."},
  %{role: :user, content: "Explain monads in detail."}
]

PortfolioManager.Router.stream(messages, fn chunk ->
  IO.write(chunk)
end)

Router streaming executes through `nsai_llm` Actions and the configured
PortfolioCore LLM adapter.
```

## CLI Streaming

Use the `--stream` flag with the ask command:

```bash
mix portfolio.ask "Explain this codebase" --stream
```

The response will stream directly to the terminal.

## Building Streaming Interfaces

### Collecting Chunks

```elixir
{:ok, agent} = Agent.start_link(fn -> [] end)

PortfolioManager.RAG.stream_query("Question", fn chunk ->
  Agent.update(agent, &[chunk | &1])
end)

full_response =
  Agent.get(agent, & &1)
  |> Enum.reverse()
  |> Enum.join()
```

### Progress Indicator

```elixir
PortfolioManager.RAG.stream_query("Question", fn chunk ->
  IO.write(chunk)
  IO.write(:stderr, ".")  # Progress dots
end)
```

### WebSocket Integration

```elixir
def handle_in("ask", %{"question" => question}, socket) do
  spawn(fn ->
    PortfolioManager.RAG.stream_query(question, fn chunk ->
      push(socket, "chunk", %{text: chunk})
    end)

    push(socket, "done", %{})
  end)

  {:noreply, socket}
end
```

### LiveView Integration

```elixir
def handle_event("ask", %{"question" => question}, socket) do
  parent = self()

  Task.start(fn ->
    PortfolioManager.RAG.stream_query(question, fn chunk ->
      send(parent, {:chunk, chunk})
    end)

    send(parent, :done)
  end)

  {:noreply, assign(socket, loading: true, response: "")}
end

def handle_info({:chunk, chunk}, socket) do
  {:noreply, update(socket, :response, &(&1 <> chunk))}
end

def handle_info(:done, socket) do
  {:noreply, assign(socket, loading: false)}
end
```

## Error Handling

```elixir
case PortfolioManager.RAG.stream_query(question, callback) do
  :ok ->
    IO.puts("\nComplete!")

  {:error, :no_healthy_providers} ->
    IO.puts("No LLM providers available")

  {:error, reason} ->
    IO.puts("Error: #{inspect(reason)}")
end
```

## Options

### RAG Options

```elixir
PortfolioManager.RAG.stream_query(question, callback,
  strategy: :hybrid,       # RAG strategy
  top_k: 5,               # Number of context documents
  index_id: "my_index"    # Vector index to search
)
```

### Router Options

```elixir
PortfolioManager.Router.stream(messages, callback,
  strategy: :fallback,    # Routing strategy
  task_type: :code        # For specialist routing
)
```

## Performance Considerations

1. **Callback overhead** - Keep callbacks lightweight
2. **Buffer size** - Chunks are typically small (a few tokens)
3. **Error propagation** - Errors in callbacks can interrupt streaming
4. **Connection handling** - Handle disconnections gracefully
