# Example 12: Editing and Removing Repositories
#
# This example demonstrates:
# - Editing repository metadata (type, status, purpose, tags)
# - Removing repositories from the portfolio
# - Bulk updates
#
# Run with: mix run examples/12_edit_and_remove.exs

IO.puts("""
================================================================================
Example 12: Editing and Removing Repositories
================================================================================
""")

# Initialize portfolio
portfolio_path = System.get_env("PORTFOLIO_PATH") || "/tmp/portfolio_manager_examples"

case PortfolioManager.init(portfolio_path) do
  {:ok, portfolio} ->
    repos = PortfolioManager.list_repos(portfolio)

    if Enum.empty?(repos) do
      IO.puts("No repositories found. Run example 01 first.")
    else
      repo = List.first(repos)
      IO.puts("Working with repository: #{repo.id}\n")

      # --- Get current state ---
      IO.puts("--- Current State ---")
      {:ok, _context} = PortfolioManager.get_context(portfolio, repo.id)
      IO.puts("  Type:    #{repo.type}")
      IO.puts("  Status:  #{repo.status}")
      IO.puts("  Tags:    #{inspect(repo.tags)}")
      IO.puts("  Purpose: #{repo.purpose || "(not set)"}")
      IO.puts("")

      # --- Edit repository metadata ---
      IO.puts("--- Editing Repository ---")

      # Update type
      IO.puts("  Setting type to :library...")
      PortfolioManager.update_context(portfolio, repo.id, %{type: :library})

      # Update status
      IO.puts("  Setting status to :active...")
      PortfolioManager.update_context(portfolio, repo.id, %{status: :active})

      # Update purpose
      IO.puts("  Setting purpose...")

      PortfolioManager.update_context(portfolio, repo.id, %{
        purpose: "Example repository for Portfolio Manager demonstrations"
      })

      # Update tags
      IO.puts("  Adding tags...")

      PortfolioManager.update_context(portfolio, repo.id, %{
        tags: ["example", "demo", "elixir", "portfolio"]
      })

      IO.puts("  Updates applied.\n")

      # --- Verify changes ---
      IO.puts("--- After Editing ---")
      {:ok, repo_updated} = PortfolioManager.get_repo(portfolio, repo.id)
      IO.puts("  Type:    #{repo_updated.type}")
      IO.puts("  Status:  #{repo_updated.status}")
      IO.puts("  Tags:    #{inspect(repo_updated.tags)}")
      IO.puts("  Purpose: #{repo_updated.purpose || "(not set)"}")
      IO.puts("")

      # --- Demonstrate remove (with a dummy repo) ---
      IO.puts("--- Remove Repository (Demo) ---")

      # Create a temporary test repo to remove
      temp_dir = Path.join(System.tmp_dir!(), "temp_repo_#{:rand.uniform(10000)}")
      File.mkdir_p!(temp_dir)
      File.write!(Path.join(temp_dir, "README.md"), "# Temp Repo")

      # Initialize git in temp dir
      {_, 0} = System.cmd("git", ["init"], cd: temp_dir, stderr_to_stdout: true)
      {_, 0} = System.cmd("git", ["add", "."], cd: temp_dir, stderr_to_stdout: true)
      {_, 0} = System.cmd("git", ["commit", "-m", "init"], cd: temp_dir, stderr_to_stdout: true)

      # Add the temp repo
      IO.puts("  Adding temporary repo: #{temp_dir}")

      case PortfolioManager.add(portfolio, temp_dir) do
        {:ok, added_repo} ->
          IO.puts("  Added repo: #{added_repo.id}")

          # Count before remove
          count_before = length(PortfolioManager.list_repos(portfolio))
          IO.puts("  Repos count before: #{count_before}")

          # Remove it
          IO.puts("  Removing repo...")

          case PortfolioManager.remove(portfolio, added_repo.id) do
            :ok ->
              count_after = length(PortfolioManager.list_repos(portfolio))
              IO.puts("  Repos count after:  #{count_after}")
              IO.puts("  Successfully removed!")

            {:error, reason} ->
              IO.puts("  Remove failed: #{inspect(reason)}")
          end

        {:error, reason} ->
          IO.puts("  Could not add temp repo: #{inspect(reason)}")
      end

      # Cleanup temp dir
      File.rm_rf!(temp_dir)

      # Save changes
      IO.puts("\nSaving portfolio...")
      PortfolioManager.sync(portfolio)
      IO.puts("  Done.")
    end

  {:error, reason} ->
    IO.puts("Failed to initialize portfolio: #{inspect(reason)}")
    IO.puts("Run example 01 first to set up the portfolio.")
end

IO.puts("""

================================================================================
Example 12 Complete!
================================================================================
Demonstrated editing repository metadata and removing repositories.
""")
