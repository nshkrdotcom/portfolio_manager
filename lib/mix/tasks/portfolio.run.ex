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

  alias PortfolioManager.CLI.Exit
  alias PortfolioManager.Workflow.Engine

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

      args != [] ->
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
    Enum.map_join(workflows, "\n", fn wf ->
      name = String.pad_trailing(wf.name, 20)
      "  #{name} #{wf.description}"
    end)
  end

  defp run_workflow(workflow_name, opts) do
    portfolio_path = opts[:portfolio_dir] || default_portfolio_path()

    case PortfolioManager.init(portfolio_path) do
      {:ok, portfolio} -> execute_workflow(portfolio, workflow_name, opts)
      {:error, :not_initialized} -> handle_not_initialized(portfolio_path)
    end
  end

  defp execute_workflow(portfolio, workflow_name, opts) do
    print_verbose_header(workflow_name, opts)
    engine_opts = build_engine_opts(portfolio, opts)

    Engine.run(workflow_name, engine_opts)
    |> handle_workflow_result(workflow_name, opts)
  end

  defp print_verbose_header(workflow_name, opts) do
    if opts[:verbose] do
      Mix.shell().info("#{IO.ANSI.cyan()}Running workflow: #{workflow_name}#{IO.ANSI.reset()}")
      if opts[:repo], do: Mix.shell().info("Target repo: #{opts[:repo]}")
      if opts[:dry_run], do: Mix.shell().info("#{IO.ANSI.yellow()}(dry run)#{IO.ANSI.reset()}")
      Mix.shell().info("")
    end
  end

  defp build_engine_opts(portfolio, opts) do
    inputs = if opts[:repo], do: %{"repo_id" => opts[:repo]}, else: %{}

    [
      portfolio: portfolio,
      inputs: inputs,
      dry_run: opts[:dry_run] || false,
      verbose: opts[:verbose] || false
    ]
  end

  defp handle_not_initialized(portfolio_path) do
    Mix.shell().error("""
    Portfolio not found at #{portfolio_path}
    Run `mix portfolio.init` first.
    """)

    Exit.halt(:config)
  end

  defp handle_workflow_result({:ok, result}, workflow_name, opts) do
    if opts[:json] do
      Mix.shell().info(Jason.encode!(result, pretty: true))
    else
      output_result(workflow_name, result, opts)
    end
  end

  defp handle_workflow_result({:error, :not_found}, workflow_name, _opts) do
    Mix.shell().error("Workflow '#{workflow_name}' not found")
    Mix.shell().info("")
    Mix.shell().info("Run `mix portfolio.run --list` to see available workflows")
    Exit.halt(:invalid_args)
  end

  defp handle_workflow_result({:error, reason}, _workflow_name, _opts) do
    Mix.shell().error("Workflow failed: #{inspect(reason)}")
    Exit.halt(:error)
  end

  defp format_step_detail(:error, msg) when is_binary(msg), do: " - #{msg}"
  defp format_step_detail(:skipped, msg) when is_binary(msg), do: " - #{msg}"
  defp format_step_detail(_status, _detail), do: ""

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
      Enum.each(result.details, &print_step_detail/1)
    end
  end

  defp print_step_detail({step_name, status, detail}) do
    status_str =
      case status do
        :ok -> "#{IO.ANSI.green()}✓#{IO.ANSI.reset()}"
        :skipped -> "#{IO.ANSI.yellow()}○#{IO.ANSI.reset()}"
        :error -> "#{IO.ANSI.red()}✗#{IO.ANSI.reset()}"
      end

    detail_str = format_step_detail(status, detail)
    Mix.shell().info("  #{status_str} #{step_name}#{detail_str}")
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
