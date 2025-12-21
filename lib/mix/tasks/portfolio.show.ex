defmodule Mix.Tasks.Portfolio.Show do
  @moduledoc """
  Show detailed information about a repository.

  ## Usage

      mix portfolio.show <repo-id> [options]

  ## Options

    * `--json` - Output as JSON
    * `--section` - Show specific section (context, notes, decisions)
    * `--help` - Show help message

  ## Examples

      mix portfolio.show my-project
      mix portfolio.show my-project --section=notes
      mix portfolio.show my-project --json

  """
  @shortdoc "Show detailed repo information"

  use Mix.Task

  @impl Mix.Task
  def run(args) do
    {opts, args, _} =
      OptionParser.parse(args,
        strict: [
          json: :boolean,
          section: :string,
          help: :boolean,
          portfolio_dir: :string
        ],
        aliases: [d: :portfolio_dir]
      )

    if opts[:help] do
      show_help()
    else
      case args do
        [repo_id | _] ->
          show_repo(repo_id, opts)

        [] ->
          Mix.shell().error("Missing repo-id. Usage: mix portfolio.show <repo-id>")
      end
    end
  end

  defp show_repo(repo_id, opts) do
    portfolio_path = opts[:portfolio_dir] || default_portfolio_path()

    case PortfolioManager.init(portfolio_path) do
      {:ok, portfolio} ->
        case PortfolioManager.get_context(portfolio, repo_id) do
          {:ok, context} ->
            if opts[:json] do
              output_json(context)
            else
              output_formatted(context, opts[:section])
            end

          {:error, :not_found} ->
            Mix.shell().error("Repository '#{repo_id}' not found.")
        end

      {:error, :not_initialized} ->
        Mix.shell().error("Portfolio not found. Run `mix portfolio.init` first.")
    end
  end

  defp output_json(context) do
    data = %{
      repo: %{
        id: context.repo.id,
        name: context.repo.name,
        type: context.repo.type,
        status: context.repo.status,
        language: context.repo.language,
        path: context.repo.path,
        remote_url: context.repo.remote_url,
        tags: context.repo.tags
      },
      notes: context.notes,
      decisions: context.decisions,
      todos: context.todos
    }

    Mix.shell().info(Jason.encode!(data, pretty: true))
  end

  defp output_formatted(context, section) do
    repo = context.repo

    case section do
      "notes" ->
        output_notes(context.notes)

      "decisions" ->
        output_decisions(context.decisions)

      "todos" ->
        output_todos(context.todos)

      _ ->
        output_full(repo, context)
    end
  end

  defp output_full(repo, context) do
    Mix.shell().info("""
    #{IO.ANSI.bright()}#{repo.name || repo.id}#{IO.ANSI.reset()}
    #{String.duplicate("═", 60)}

    Type:        #{repo.type} (#{repo.language})
    Status:      #{repo.status}#{priority_str(repo.priority)}
    Path:        #{repo.path}
    #{remote_str(repo.remote_url)}
    #{purpose_str(repo.purpose)}
    #{tags_str(repo.tags)}
    #{todos_summary(context.todos)}
    #{decisions_summary(context.decisions)}
    #{notes_summary(context.notes)}
    """)
  end

  defp output_notes(nil), do: Mix.shell().info("No notes.")

  defp output_notes(notes) do
    Mix.shell().info(notes)
  end

  defp output_decisions([]), do: Mix.shell().info("No decisions.")

  defp output_decisions(decisions) do
    Mix.shell().info("Decisions:")

    Enum.each(decisions, fn d ->
      Mix.shell().info("  #{d.id} - #{d.title}")
      Mix.shell().info("    #{d.content}")
      Mix.shell().info("")
    end)
  end

  defp output_todos([]), do: Mix.shell().info("No todos.")

  defp output_todos(todos) do
    Mix.shell().info("Todos:")

    Enum.each(todos, fn todo ->
      Mix.shell().info("  • #{todo}")
    end)
  end

  defp priority_str(nil), do: ""
  defp priority_str(:unknown), do: ""
  defp priority_str(priority), do: ", #{priority} priority"

  defp remote_str(nil), do: ""
  defp remote_str(url), do: "Remote:      #{url}"

  defp purpose_str(nil), do: ""

  defp purpose_str(purpose) do
    """

    Purpose:
      #{String.slice(purpose, 0, 200)}
    """
  end

  defp tags_str([]), do: ""
  defp tags_str(nil), do: ""
  defp tags_str(tags), do: "Tags:        #{Enum.join(tags, ", ")}"

  defp todos_summary([]), do: ""

  defp todos_summary(todos) do
    """
    Todos:
    #{Enum.map_join(Enum.take(todos, 3), "\n", fn t -> "  • #{t}" end)}
    """
  end

  defp decisions_summary([]), do: ""

  defp decisions_summary(decisions) do
    """
    Recent Decisions:
    #{Enum.map_join(Enum.take(decisions, 3), "\n", fn d -> "  #{d.id} - #{d.title}" end)}
    """
  end

  defp notes_summary(nil), do: ""

  defp notes_summary(notes) do
    line_count = length(String.split(notes, "\n"))
    "Notes: (#{line_count} lines) → mix portfolio.show <id> --section=notes"
  end

  defp show_help do
    Mix.shell().info("""
    Usage: mix portfolio.show <repo-id> [options]

    Show detailed information about a repository.

    Options:
      --json           Output as JSON
      --section        Show specific section (notes, decisions, todos)
      --help           Show this help message

    Examples:
      mix portfolio.show my-project
      mix portfolio.show my-project --section=notes
      mix portfolio.show my-project --json
    """)
  end

  defp default_portfolio_path do
    System.get_env("PORTFOLIO_DIR") || Path.join(System.user_home!(), ".portfolio")
  end
end
