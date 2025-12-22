defmodule Mix.Tasks.Portfolio.Run do
  @moduledoc """
  Run a workflow on repositories.

  ## Usage

      mix portfolio.run <workflow> [options]

  ## Options

    * `--repo`, `-r` - Target repository ID
    * `--dry-run` - Show what would happen without executing
    * `--verbose`, `-v` - Show detailed output
    * `--list` - List available workflows
    * `--json` - Output results as JSON
    * `--help` - Show help message

  ## Built-in Workflows

    * `port-check` - Check port status against upstream
    * `port-sync` - Sync port with upstream changes
    * `health-check` - Run health checks on repos
    * `doc-generate` - Generate documentation
    * `initial-setup` - Initial setup for new repos

  ## Examples

      # List available workflows
      mix portfolio.run --list

      # Run a workflow on a specific repo
      mix portfolio.run port-check --repo=my-port

      # Dry run to see what would happen
      mix portfolio.run health-check --dry-run --verbose

  """
  @shortdoc "Run a workflow"

  use Mix.Task

  alias PortfolioManager.Workflow.Engine
  alias PortfolioManager.CLI.Exit

  @impl Mix.Task
  def run(args) do
    {opts, args, _} =
      OptionParser.parse(args,
        strict: [
          repo: :string,
          dry_run: :boolean,
          verbose: :boolean,
          list: :boolean,
          json: :boolean,
          help: :boolean,
          portfolio_dir: :string
        ],
        aliases: [r: :repo, v: :verbose, d: :portfolio_dir]
      )

    cond do
      opts[:help] ->
        show_help()

      opts[:list] ->
        list_workflows(opts)

      length(args) >= 1 ->
        run_workflow(List.first(args), opts)

      true ->
        show_help()
        Exit.halt(:invalid_args)
    end
  end

  defp list_workflows(opts) do
    workflows = Engine.list_workflows()

    if opts[:json] do
      Mix.shell().info(Jason.encode!(workflows, pretty: true))
    else
      if Enum.empty?(workflows) do
        Mix.shell().info("No workflows found.")
        Mix.shell().info("")
        Mix.shell().info("Create workflows in:")
        Mix.shell().info("  * ~/portfolio/workflows/*.yml")
        Mix.shell().info("  * repos/{id}/workflows/*.yml")
      else
        Mix.shell().info("""
        #{IO.ANSI.cyan()}Available Workflows#{IO.ANSI.reset()}

        #{format_workflows(workflows)}
        """)
      end
    end
  end

  defp format_workflows(workflows) do
    workflows
    |> Enum.map(fn wf ->
      name = String.pad_trailing(wf.name, 20)
      "  #{name} #{wf.description}"
    end)
    |> Enum.join("\n")
  end

  defp run_workflow(workflow_name, opts) do
    portfolio_path = opts[:portfolio_dir] || default_portfolio_path()

    case PortfolioManager.init(portfolio_path) do
      {:ok, portfolio} ->
        if opts[:verbose] do
          Mix.shell().info(
            "#{IO.ANSI.cyan()}Running workflow: #{workflow_name}#{IO.ANSI.reset()}"
          )

          if opts[:repo] do
            Mix.shell().info("Target repo: #{opts[:repo]}")
          end

          if opts[:dry_run] do
            Mix.shell().info("#{IO.ANSI.yellow()}(dry run)#{IO.ANSI.reset()}")
          end

          Mix.shell().info("")
        end

        inputs = if opts[:repo], do: %{"repo_id" => opts[:repo]}, else: %{}

        engine_opts = [
          portfolio: portfolio,
          inputs: inputs,
          dry_run: opts[:dry_run] || false,
          verbose: opts[:verbose] || false
        ]

        case Engine.run(workflow_name, engine_opts) do
          {:ok, result} ->
            if opts[:json] do
              Mix.shell().info(Jason.encode!(result, pretty: true))
            else
              output_result(workflow_name, result, opts)
            end

          {:error, :not_found} ->
            Mix.shell().error("Workflow '#{workflow_name}' not found")
            Mix.shell().info("")
            Mix.shell().info("Run `mix portfolio.run --list` to see available workflows")
            Exit.halt(:invalid_args)

          {:error, reason} ->
            Mix.shell().error("Workflow failed: #{inspect(reason)}")
            Exit.halt(:error)
        end

      {:error, :not_initialized} ->
        Mix.shell().error("""
        Portfolio not found at #{portfolio_path}
        Run `mix portfolio.init` first.
        """)

        Exit.halt(:config)
    end
  end

  defp output_result(workflow_name, result, opts) do
    status_icon =
      if result.failed == 0,
        do: IO.ANSI.green() <> "✓" <> IO.ANSI.reset(),
        else: IO.ANSI.red() <> "✗" <> IO.ANSI.reset()

    Mix.shell().info("""
    #{status_icon} Workflow '#{workflow_name}' completed

    Steps: #{result.completed}/#{result.steps} completed
    #{if result.failed > 0, do: "Failed: #{result.failed}", else: ""}
    #{if result.skipped > 0, do: "Skipped: #{result.skipped}", else: ""}
    """)

    if opts[:verbose] and result.details do
      Mix.shell().info("Details:")

      Enum.each(result.details, fn {step_name, status, detail} ->
        status_str =
          case status do
            :ok -> "#{IO.ANSI.green()}✓#{IO.ANSI.reset()}"
            :skipped -> "#{IO.ANSI.yellow()}○#{IO.ANSI.reset()}"
            :error -> "#{IO.ANSI.red()}✗#{IO.ANSI.reset()}"
          end

        detail_str =
          case {status, detail} do
            {:error, msg} when is_binary(msg) -> " - #{msg}"
            {:skipped, msg} when is_binary(msg) -> " - #{msg}"
            _ -> ""
          end

        Mix.shell().info("  #{status_str} #{step_name}#{detail_str}")
      end)
    end
  end

  defp show_help do
    Mix.shell().info("""
    Usage: mix portfolio.run <workflow> [options]

    Run a workflow on repositories.

    Options:
      --repo, -r       Target repository ID
      --dry-run        Show what would happen without executing
      --verbose, -v    Show detailed output
      --list           List available workflows
      --json           Output results as JSON
      --help           Show this help message

    Built-in Workflows:
      port-check       Check port status against upstream
      port-sync        Sync port with upstream changes
      health-check     Run health checks on repos
      doc-generate     Generate documentation
      initial-setup    Initial setup for new repos

    Examples:
      mix portfolio.run --list
      mix portfolio.run port-check --repo=my-port
      mix portfolio.run health-check --dry-run --verbose
    """)
  end

  defp default_portfolio_path do
    System.get_env("PORTFOLIO_DIR") || Path.join(System.user_home!(), "portfolio")
  end
end
