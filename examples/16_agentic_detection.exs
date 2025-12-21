# Example 16: Agentic Detection
#
# This example demonstrates LLM-powered repository analysis:
# - Purpose detection from code analysis
# - Type inference (library, application, port, etc.)
# - Relationship discovery
# - Status assessment
# - Full analysis combining all detection methods
#
# Note: Requires GOOGLE_API_KEY environment variable for LLM features.
#
# Run with: mix run examples/16_agentic_detection.exs

alias PortfolioManager.Detection.Agentic

IO.puts("""
================================================================================
Example 16: Agentic Detection (LLM-Powered Analysis)
================================================================================
""")

# Check for API key
api_key = System.get_env("GOOGLE_API_KEY")
has_api_key = api_key != nil and api_key != ""

IO.puts("--- Configuration ---")
IO.puts("  GOOGLE_API_KEY: #{if has_api_key, do: "set", else: "NOT SET"}")

if not has_api_key do
  IO.puts("""

  Agentic detection requires GOOGLE_API_KEY for LLM features.
  Set it with: export GOOGLE_API_KEY="your-key"

  Running in demo mode (showing API structure only).
  """)
end

IO.puts("")

# Initialize portfolio
portfolio_path = System.get_env("PORTFOLIO_PATH") || "/tmp/portfolio_manager_examples"

case PortfolioManager.init(portfolio_path) do
  {:ok, portfolio} ->
    repos = PortfolioManager.list_repos(portfolio)

    if Enum.empty?(repos) do
      IO.puts("No repositories found. Run example 01 first.")
    else
      repo = List.first(repos)
      IO.puts("Analyzing repository: #{repo.id}")
      IO.puts("Path: #{repo.path}")
      IO.puts("")

      if has_api_key do
        # --- Detect Purpose ---
        IO.puts("--- Detecting Purpose ---")
        IO.puts("  (Analyzing code structure and documentation...)")

        case Agentic.detect_purpose(repo.path) do
          {:ok, %{purpose: purpose, confidence: conf}} ->
            IO.puts("  Detected purpose (confidence: #{Float.round(conf, 2)}):")
            IO.puts("    #{purpose}")

          {:error, reason} ->
            IO.puts("  Detection failed: #{inspect(reason)}")
        end

        IO.puts("")

        # --- Detect Type ---
        IO.puts("--- Detecting Type ---")
        IO.puts("  (Inferring project type from structure...)")

        case Agentic.detect_type(repo.path) do
          {:ok, %{type: type, confidence: conf}} ->
            IO.puts("  Detected type: #{type} (confidence: #{Float.round(conf, 2)})")

            IO.puts(
              "  Valid types: library, application, port, fork, experiment, template, config, docs"
            )

          {:error, reason} ->
            IO.puts("  Detection failed: #{inspect(reason)}")
        end

        IO.puts("")

        # --- Detect Status ---
        IO.puts("--- Detecting Status ---")
        IO.puts("  (Analyzing activity and health indicators...)")

        case Agentic.detect_status(repo.path) do
          {:ok, %{status: status, confidence: conf}} ->
            IO.puts("  Detected status: #{status} (confidence: #{Float.round(conf, 2)})")
            IO.puts("  Valid statuses: active, maintenance, stale, blocked, archived")

          {:error, reason} ->
            IO.puts("  Detection failed: #{inspect(reason)}")
        end

        IO.puts("")

        # --- Detect Relationships ---
        IO.puts("--- Detecting Relationships ---")
        IO.puts("  (Discovering connections to other repos...)")

        case Agentic.detect_relationships(repo.path, portfolio) do
          {:ok, relationships} ->
            if Enum.empty?(relationships) do
              IO.puts("  No relationships detected")
            else
              IO.puts("  Detected relationships:")

              Enum.each(relationships, fn rel ->
                IO.puts("    #{rel.from} -> #{rel.to} (#{rel.type})")
              end)
            end

          {:error, reason} ->
            IO.puts("  Detection failed: #{inspect(reason)}")
        end

        IO.puts("")

        # --- Full Analysis ---
        IO.puts("--- Full Analysis ---")
        IO.puts("  (Combining all detection methods...)")

        case Agentic.analyze(repo.path, portfolio: portfolio) do
          {:ok, analysis} ->
            IO.puts("  Complete analysis:")

            purpose_str =
              case analysis[:purpose] do
                %{purpose: p} -> p
                nil -> "(not detected)"
              end

            type_str =
              case analysis[:type] do
                %{type: t} -> to_string(t)
                nil -> "(not detected)"
              end

            status_str =
              case analysis[:status] do
                %{status: s} -> to_string(s)
                nil -> "(not detected)"
              end

            IO.puts("    Purpose: #{purpose_str}")
            IO.puts("    Type:    #{type_str}")
            IO.puts("    Status:  #{status_str}")

            if analysis[:relationships] && length(analysis[:relationships]) > 0 do
              IO.puts("    Relationships: #{length(analysis[:relationships])} found")
            end

          {:error, reason} ->
            IO.puts("  Analysis failed: #{inspect(reason)}")
        end
      else
        # Demo mode - show the API structure
        IO.puts("--- API Demo (No LLM) ---")
        IO.puts("")
        IO.puts("  Available functions:")
        IO.puts("")
        IO.puts("  Agentic.detect_purpose(repo_path)")
        IO.puts("    Returns: {:ok, \"description of purpose\"}")
        IO.puts("    Uses LLM to analyze code and infer project purpose")
        IO.puts("")
        IO.puts("  Agentic.detect_type(repo_path)")
        IO.puts("    Returns: {:ok, :library | :application | :port | ...}")
        IO.puts("    Infers project type from structure and patterns")
        IO.puts("")
        IO.puts("  Agentic.detect_status(repo_path)")
        IO.puts("    Returns: {:ok, :active | :maintenance | :stale | ...}")
        IO.puts("    Assesses project health from git history and code state")
        IO.puts("")
        IO.puts("  Agentic.detect_relationships(repo_path, portfolio)")
        IO.puts("    Returns: {:ok, [%{from: _, to: _, type: _}, ...]}")
        IO.puts("    Discovers dependencies and connections to other repos")
        IO.puts("")
        IO.puts("  Agentic.analyze(repo_path, opts)")
        IO.puts("    Returns: {:ok, %{purpose: _, type: _, status: _, relationships: _}}")
        IO.puts("    Combines all detection methods for comprehensive analysis")
        IO.puts("")
        IO.puts("  Valid types: library, application, port, fork, experiment,")
        IO.puts("               template, config, docs, unknown")
        IO.puts("")
        IO.puts("  Valid statuses: active, maintenance, stale, blocked, archived, unknown")
      end
    end

  {:error, reason} ->
    IO.puts("Failed to initialize portfolio: #{inspect(reason)}")
    IO.puts("Run example 01 first to set up the portfolio.")
end

IO.puts("""

================================================================================
Example 16 Complete!
================================================================================
Demonstrated agentic detection capabilities:
- Purpose detection from code analysis
- Type inference
- Status assessment
- Relationship discovery
- Full combined analysis

These features use LLM (Gemini) to intelligently analyze repositories.
Set GOOGLE_API_KEY to enable live detection.
""")
