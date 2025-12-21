# Example 10: Multi-Turn Chat Sessions
#
# This example demonstrates:
# - Starting an interactive chat session
# - Multi-turn conversation with memory
# - Context preservation across messages
#
# REQUIRES: GOOGLE_API_KEY environment variable
#
# Run with: mix run examples/10_chat_session.exs

IO.puts("""
================================================================================
Example 10: Multi-Turn Chat Sessions
================================================================================
""")

# Check for API key
unless System.get_env("GOOGLE_API_KEY") do
  IO.puts("""
  ⚠️  GOOGLE_API_KEY not set!

  Chat sessions require a Gemini API key.
  Set it with: export GOOGLE_API_KEY="your-api-key"

  Skipping chat session examples.
  """)

  System.halt(0)
end

IO.puts("✓ GOOGLE_API_KEY detected")

# Initialize portfolio
portfolio_path = System.get_env("PORTFOLIO_EXAMPLES_PATH", "/tmp/portfolio_manager_examples")

unless File.exists?(portfolio_path) do
  IO.puts("Portfolio not found. Run example 01 first.")
  System.halt(1)
end

{:ok, portfolio} = PortfolioManager.init(portfolio_path)

# Check we have repos
repos = PortfolioManager.list_repos(portfolio)
IO.puts("Portfolio has #{length(repos)} repositories\n")

if length(repos) == 0 do
  IO.puts("No repositories found. Run example 01 first.")
  System.halt(1)
end

IO.puts("""
Multi-turn chat maintains conversation context.
The agent remembers previous messages and can reference them.
""")

# Start a session
IO.puts("Starting chat session...")
{:ok, session} = PortfolioManager.start_session(portfolio)
IO.puts("✓ Session started\n")

# Conversation messages
conversation = [
  "How many repositories do I have?",
  "Which ones are Elixir projects?",
  "Tell me more about the first one you mentioned",
  "What's the overall health of my portfolio?"
]

# Run conversation
IO.puts(String.duplicate("═", 60))
IO.puts("CONVERSATION")
IO.puts(String.duplicate("═", 60))

_final_session =
  Enum.reduce(conversation, session, fn message, current_session ->
    IO.puts("\n👤 User: #{message}")

    next_session =
      try do
        case PortfolioManager.chat(portfolio, current_session, message) do
          {:ok, response, updated_session} ->
            # Format response (truncate if too long)
            formatted_response =
              if String.length(response) > 500 do
                String.slice(response, 0, 500) <> "..."
              else
                response
              end

            IO.puts("\n🤖 Assistant: #{formatted_response}")
            updated_session

          {:error, reason} ->
            IO.puts("\n❌ Error: #{inspect(reason)}")
            current_session
        end
      rescue
        e ->
          IO.puts("\n❌ Exception: #{Exception.message(e)}")
          current_session
      end

    # Delay between messages
    Process.sleep(1500)
    next_session
  end)

IO.puts("\n" <> String.duplicate("═", 60))

IO.puts("""

How Chat Sessions Work:
  1. Each session maintains a message history
  2. Previous messages provide context for new questions
  3. "The first one" or "tell me more" work because of history
  4. Sessions can be persisted and resumed later

Session Features:
  - Message history with roles (user, assistant, tool)
  - Context storage for additional state
  - Token estimation for context window management

================================================================================
Example 10 Complete!
================================================================================
""")
