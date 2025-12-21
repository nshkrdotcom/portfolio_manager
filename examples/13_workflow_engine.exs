# Example 13: Workflow Engine
#
# This example demonstrates:
# - Listing available workflows
# - Running workflows with options
# - Creating custom workflows
# - Workflow step types (git, shell, file, context)
#
# Run with: mix run examples/13_workflow_engine.exs

alias PortfolioManager.Workflow.{Engine, Parser, Context}

IO.puts("""
================================================================================
Example 13: Workflow Engine
================================================================================
""")

# Initialize portfolio
portfolio_path = System.get_env("PORTFOLIO_PATH") || "/tmp/portfolio_manager_examples"

case PortfolioManager.init(portfolio_path) do
  {:ok, portfolio} ->
    repos = PortfolioManager.list_repos(portfolio)

    # --- List available workflows ---
    IO.puts("--- Available Workflows ---")
    workflows = Engine.list_workflows()

    if Enum.empty?(workflows) do
      IO.puts("  No workflows found.")
      IO.puts("  Workflows are loaded from:")
      IO.puts("    - priv/workflows/*.yml (built-in)")
      IO.puts("    - ~/.portfolio/workflows/*.yml (user)")
    else
      Enum.each(workflows, fn wf ->
        IO.puts("  #{String.pad_trailing(wf.name, 20)} - #{wf.description}")
      end)
    end

    IO.puts("")

    # --- Get workflow details ---
    IO.puts("--- Workflow Details ---")

    case Engine.get_workflow("health-check") do
      {:ok, workflow} ->
        IO.puts("  Name: #{workflow.name}")
        IO.puts("  Description: #{workflow.description}")
        IO.puts("  Steps:")

        Enum.each(workflow.steps, fn step ->
          IO.puts("    - #{step.name} (#{step.type})")
        end)

      {:error, :not_found} ->
        IO.puts("  health-check workflow not found")
    end

    IO.puts("")

    # --- Create and parse a custom workflow ---
    IO.puts("--- Custom Workflow (In-Memory) ---")

    workflow_yaml = """
    name: example-workflow
    description: Example workflow for demonstration

    vars:
      project_name: my-project
      output_dir: /tmp

    steps:
      - name: check-directory
        type: shell
        command: pwd
        description: Show current directory

      - name: list-files
        type: shell
        command: ls -la
        description: List files

      - name: create-timestamp
        type: context
        action: set
        key: timestamp
        value: "{{env.PWD}}"
        description: Store timestamp in context

      - name: show-context
        type: context
        action: get
        key: timestamp
        description: Retrieve from context
    """

    case Parser.parse_string(workflow_yaml) do
      {:ok, workflow} ->
        IO.puts("  Parsed workflow: #{workflow.name}")
        IO.puts("  Steps: #{length(workflow.steps)}")
        IO.puts("  Variables: #{inspect(workflow.vars)}")

      {:error, reason} ->
        IO.puts("  Parse error: #{inspect(reason)}")
    end

    IO.puts("")

    # --- Run a workflow (dry-run) ---
    IO.puts("--- Running Workflow (Dry Run) ---")

    if Enum.any?(repos) do
      repo = List.first(repos)

      case Engine.run("health-check",
             portfolio: portfolio,
             repo_id: repo.id,
             dry_run: true,
             verbose: true
           ) do
        {:ok, result} ->
          IO.puts("\n  Result:")
          IO.puts("    Steps:     #{result.steps}")
          IO.puts("    Completed: #{result.completed}")
          IO.puts("    Failed:    #{result.failed}")
          IO.puts("    Skipped:   #{result.skipped}")

        {:error, :not_found} ->
          IO.puts("  Workflow not found. Creating workflows directory...")

          # Create a simple workflow for testing
          workflows_dir = Path.join(portfolio_path, "workflows")
          File.mkdir_p!(workflows_dir)

          simple_workflow = """
          name: simple-check
          description: Simple status check

          steps:
            - name: show-info
              type: shell
              command: echo "Checking repository"
          """

          File.write!(Path.join(workflows_dir, "simple-check.yml"), simple_workflow)
          IO.puts("  Created simple-check.yml workflow")

        {:error, reason} ->
          IO.puts("  Error: #{inspect(reason)}")
      end
    else
      IO.puts("  No repositories to run workflow on.")
    end

    IO.puts("")

    # --- Workflow Context ---
    IO.puts("--- Workflow Context Demo ---")

    ctx =
      Context.new(%{
        workflow: "demo",
        vars: %{"name" => "test", "version" => "1.0"}
      })

    IO.puts("  Created context for workflow: #{ctx.workflow}")
    IO.puts("  Initial vars: #{inspect(ctx.vars)}")

    # Set a variable
    ctx = Context.set_var(ctx, "custom_key", "custom_value")
    IO.puts("  After set_var: #{inspect(ctx.vars)}")

    # Interpolate a template
    template = "Project {{name}} version {{version}} - {{custom_key}}"
    result = Context.interpolate(ctx, template)
    IO.puts("  Interpolated: #{result}")

    # Evaluate conditions
    IO.puts("\n  Condition evaluation:")
    IO.puts("    'name == test': #{Context.evaluate_condition(ctx, "name == test")}")
    IO.puts("    'version != 2.0': #{Context.evaluate_condition(ctx, "version != 2.0")}")
    IO.puts("    'custom_key': #{Context.evaluate_condition(ctx, "custom_key")}")
    IO.puts("    '!missing': #{Context.evaluate_condition(ctx, "!missing")}")

  {:error, reason} ->
    IO.puts("Failed to initialize portfolio: #{inspect(reason)}")
    IO.puts("Run example 01 first to set up the portfolio.")
end

IO.puts("""

================================================================================
Example 13 Complete!
================================================================================
Demonstrated workflow engine: listing, parsing, running, and context management.

To create custom workflows, add YAML files to:
  ~/.portfolio/workflows/

Built-in workflows are in:
  priv/workflows/
""")
