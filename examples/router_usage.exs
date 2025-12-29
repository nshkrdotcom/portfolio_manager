# Router Usage Example
#
# This example demonstrates multi-provider LLM routing.
#
# Run with: mix run examples/router_usage.exs

IO.puts("=== Router Usage Example ===\n")

# Check current strategy
strategy = PortfolioManager.Router.get_strategy()
IO.puts("Current strategy: #{strategy}")

# List providers
providers = PortfolioManager.Router.list_providers()
IO.puts("Registered providers: #{length(providers)}")

Enum.each(providers, fn p ->
  health = PortfolioManager.Router.health_check(p.name)
  IO.puts("  - #{p.name} (priority: #{p.priority}, health: #{health})")
  IO.puts("    capabilities: #{inspect(p.capabilities)}")
end)

IO.puts("")

# Simple completion
IO.puts("Sending a simple request...")

messages = [
  %{role: :user, content: "What is 2 + 2? Answer with just the number."}
]

case PortfolioManager.Router.complete(messages) do
  {:ok, response} ->
    IO.puts("Response: #{response.content}")

  {:error, reason} ->
    IO.puts("Error: #{inspect(reason)}")
end

IO.puts("")

# Task-specific routing (with specialist strategy)
IO.puts("Testing specialist routing for code task...")

PortfolioManager.Router.set_strategy(:specialist)

code_messages = [
  %{role: :user, content: "Write a simple Elixir function that adds two numbers."}
]

case PortfolioManager.Router.complete(code_messages, task_type: :code) do
  {:ok, response} ->
    IO.puts("Code response:\n#{response.content}")

  {:error, reason} ->
    IO.puts("Error: #{inspect(reason)}")
end

IO.puts("")

# Streaming example
IO.puts("Testing streaming response...")
IO.write("Streaming: ")

stream_messages = [
  %{role: :user, content: "Count from 1 to 5, one number per line."}
]

case PortfolioManager.Router.stream(stream_messages, &IO.write/1) do
  :ok ->
    IO.puts("\n\nStreaming complete!")

  {:error, reason} ->
    IO.puts("\nStreaming error: #{inspect(reason)}")
end

IO.puts("\n=== Example Complete ===")
