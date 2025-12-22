defmodule Mix.Tasks.Portfolio.Show do
  @moduledoc """
  Show detailed information about a repository.

  ## Usage

      mix portfolio.show <repo-id> [options]

  ## Options

    * `--json` - Output as JSON
    * `--section` - Show specific section (context, notes, decisions, port)
    * `--related` - Include related repositories
    * `--help` - Show help message

  ## Examples

      mix portfolio.show my-project
      mix portfolio.show my-project --section=notes
      mix portfolio.show my-project --json

  """
  @shortdoc "Show detailed repo information"

  use Mix.Task

  alias PortfolioManager.CLI.Exit

  @impl Mix.Task
  def run(args) do
    {opts, args, _} =
      OptionParser.parse(args,
        strict: [
          json: :boolean,
          section: :string,
          related: :boolean,
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
          Exit.halt(:invalid_args)
      end
    end
  end

  defp show_repo(repo_id, opts) do
    portfolio_path = opts[:portfolio_dir] || default_portfolio_path()

    case PortfolioManager.init(portfolio_path) do
      {:ok, portfolio} ->
        case PortfolioManager.get_context(portfolio, repo_id) do
          {:ok, context} ->
            relationships = PortfolioManager.get_relationships(portfolio, repo_id)

            if opts[:json] do
              output_json(context, relationships)
            else
              output_formatted(context, relationships, opts[:section], opts[:related])
            end

          {:error, :not_found} ->
            Mix.shell().error("Repository '#{repo_id}' not found.")
            Exit.halt(:not_found)
        end

      {:error, :not_initialized} ->
        Mix.shell().error("Portfolio not found. Run `mix portfolio.init` first.")
        Exit.halt(:config)
    end
  end

  defp output_json(context, relationships) do
    data = %{
      repo: %{
        id: context.repo.id,
        name: context.repo.name,
        type: context.repo.type,
        status: context.repo.status,
        language: context.repo.language,
        framework: context.repo.framework,
        path: context.repo.path,
        remote_url: context.repo.remote_url,
        tags: context.repo.tags
      },
      notes: context.notes,
      decisions: context.decisions,
      todos: context.todos,
      computed: context.computed,
      relationships: Enum.map(relationships, &relationship_to_map/1)
    }

    Mix.shell().info(Jason.encode!(data, pretty: true))
  end

  defp output_formatted(context, relationships, section, related?) do
    repo = context.repo

    case section do
      "notes" ->
        output_notes(context.notes)

      "decisions" ->
        output_decisions(context.decisions)

      "todos" ->
        output_todos(context.todos)

      "port" ->
        output_port(repo.port)

      "context" ->
        output_context(repo)

      _ ->
        output_full(repo, context, relationships, related?)
    end
  end

  defp output_full(repo, context, relationships, related?) do
    computed = context.computed

    Mix.shell().info("""
    #{IO.ANSI.bright()}#{repo.name || repo.id}#{IO.ANSI.reset()}
    #{String.duplicate("═", 60)}

    Type:        #{repo.type} (#{repo.language})
    Status:      #{repo.status}#{priority_str(repo.priority)}
    Path:        #{repo.path}
    #{remote_str(repo.remote_url)}
    #{framework_str(repo.framework)}
    #{purpose_str(repo.purpose)}
    #{tags_str(repo.tags)}
    #{stats_summary(computed)}
    #{dependencies_summary(computed)}
    #{relationships_summary(repo.id, relationships, related?)}
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
  defp tags_str(tags), do: "Tags:        #{Enum.join(tags, ", ")}"

  defp framework_str(nil), do: ""
  defp framework_str(framework), do: "Framework:   #{framework}"

  defp stats_summary(computed) do
    commit_count = Map.get(computed, "commit_count_30d") || Map.get(computed, :commit_count_30d)
    contributors = Map.get(computed, "contributors") || Map.get(computed, :contributors) || []
    last_commit = Map.get(computed, "last_commit") || Map.get(computed, :last_commit) || %{}

    last_commit_display =
      case last_commit do
        %{"date" => date, "sha" => sha} when is_binary(date) and is_binary(sha) ->
          "#{date} (#{String.slice(sha, 0, 7)})"

        %{"date" => date} when is_binary(date) ->
          date

        %{date: date, sha: sha} when is_binary(date) and is_binary(sha) ->
          "#{date} (#{String.slice(sha, 0, 7)})"

        %{date: date} when is_binary(date) ->
          date

        _ ->
          "N/A"
      end

    """
    Stats:
      Last commit:      #{last_commit_display}
      Commits (30d):    #{commit_count || "N/A"}
      Contributors:     #{length(contributors)}
    """
  end

  defp dependencies_summary(computed) do
    deps = Map.get(computed, "dependencies") || Map.get(computed, :dependencies) || %{}
    runtime = Map.get(deps, "runtime") || Map.get(deps, :runtime) || []

    if runtime == [] do
      ""
    else
      "Dependencies (runtime):\n  " <> Enum.join(runtime, ", ")
    end
  end

  defp relationships_summary(_repo_id, [], _related?), do: ""

  defp relationships_summary(repo_id, relationships, related?) do
    lines =
      relationships
      |> Enum.map(&format_relationship(&1, repo_id))
      |> Enum.reject(&is_nil/1)

    related =
      if related? do
        related_ids =
          relationships
          |> Enum.map(fn rel -> if rel.from == repo_id, do: rel.to, else: rel.from end)
          |> Enum.uniq()

        if related_ids == [] do
          ""
        else
          "Related Repos:\n  " <> Enum.join(related_ids, ", ")
        end
      else
        ""
      end

    """
    Relationships:
    #{Enum.map_join(lines, "\n", fn line -> "  #{line}" end)}
    #{related}
    """
  end

  defp format_relationship(rel, repo_id) do
    cond do
      rel.from == repo_id ->
        "→ #{rel.to} (#{rel.type})"

      rel.to == repo_id ->
        "← #{rel.from} (#{rel.type})"

      true ->
        "#{rel.from} #{rel.type} #{rel.to}"
    end
  end

  defp relationship_to_map(rel) do
    %{
      from: rel.from,
      to: rel.to,
      type: rel.type,
      details: rel.details
    }
  end

  defp output_port(nil), do: Mix.shell().info("No port metadata.")

  defp output_port(port) do
    Mix.shell().info("""
    Port:
      Upstream:  #{Map.get(port, :upstream_url) || Map.get(port, "upstream_url") || "N/A"}
      Language:  #{Map.get(port, :upstream_language) || Map.get(port, "upstream_language") || "N/A"}
      Strategy:  #{Map.get(port, :strategy) || Map.get(port, "strategy") || "N/A"}
    """)
  end

  defp output_context(repo) do
    Mix.shell().info("""
    Context:
      Type:      #{repo.type}
      Status:    #{repo.status}
      Language:  #{repo.language}
      Framework: #{repo.framework || "N/A"}
    """)
  end

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
      --section        Show specific section (context, notes, decisions, todos, port)
      --related        Include related repositories
      --help           Show this help message

    Examples:
      mix portfolio.show my-project
      mix portfolio.show my-project --section=notes
      mix portfolio.show my-project --related
      mix portfolio.show my-project --json
    """)
  end

  defp default_portfolio_path do
    System.get_env("PORTFOLIO_DIR") || Path.join(System.user_home!(), "portfolio")
  end
end
