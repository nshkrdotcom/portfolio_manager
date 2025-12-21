defmodule Mix.Tasks.Portfolio.Edit do
  @moduledoc """
  Edit a repository's metadata.

  ## Usage

      mix portfolio.edit <id> [field] [value]

  ## Options

    * `--type`, `-t` - Set repository type
    * `--status`, `-s` - Set repository status
    * `--purpose`, `-p` - Set repository purpose
    * `--tags` - Set tags (comma-separated)
    * `--priority` - Set priority (high, medium, low)
    * `--note` - Add a note
    * `--decision` - Add a decision (format: "title:content")
    * `--json` - Output result as JSON
    * `--help` - Show help message

  ## Valid Types

    library, application, port, fork, experiment, template, config, docs

  ## Valid Statuses

    active, maintenance, stale, blocked, archived

  ## Examples

      mix portfolio.edit my-app --type=library
      mix portfolio.edit my-app --status=active --priority=high
      mix portfolio.edit my-app --purpose="Authentication library"
      mix portfolio.edit my-app --tags="auth,security,jwt"
      mix portfolio.edit my-app --note="Needs review before next release"
      mix portfolio.edit my-app --decision="Use JWT:After evaluating options..."

  """
  @shortdoc "Edit a repository's metadata"

  use Mix.Task

  @impl Mix.Task
  def run(args) do
    {opts, args, _} =
      OptionParser.parse(args,
        strict: [
          type: :string,
          status: :string,
          purpose: :string,
          tags: :string,
          priority: :string,
          note: :string,
          decision: :string,
          json: :boolean,
          help: :boolean,
          portfolio_dir: :string
        ],
        aliases: [t: :type, s: :status, p: :purpose, d: :portfolio_dir]
      )

    if opts[:help] do
      show_help()
    else
      case args do
        [repo_id | _] ->
          edit_repo(repo_id, opts)

        [] ->
          Mix.shell().error("Error: Repository ID is required")
          show_help()
      end
    end
  end

  defp edit_repo(repo_id, opts) do
    portfolio_path = opts[:portfolio_dir] || default_portfolio_path()

    case PortfolioManager.init(portfolio_path) do
      {:ok, portfolio} ->
        case PortfolioManager.get_repo(portfolio, repo_id) do
          {:ok, _repo} ->
            updates = build_updates(opts)

            # Handle note addition
            note_result =
              if opts[:note] do
                PortfolioManager.add_note(portfolio, repo_id, opts[:note])
              else
                {:ok, nil}
              end

            # Handle decision addition
            decision_result =
              if opts[:decision] do
                case String.split(opts[:decision], ":", parts: 2) do
                  [title, content] ->
                    PortfolioManager.add_decision(portfolio, repo_id, title, content)

                  [title] ->
                    PortfolioManager.add_decision(portfolio, repo_id, title, "")
                end
              else
                {:ok, nil}
              end

            # Handle metadata updates
            context_result =
              if map_size(updates) > 0 do
                PortfolioManager.update_context(portfolio, repo_id, updates)
              else
                PortfolioManager.get_context(portfolio, repo_id)
              end

            case {note_result, decision_result, context_result} do
              {{:ok, _}, {:ok, _}, {:ok, context}} ->
                PortfolioManager.sync(portfolio)

                if opts[:json] do
                  output_json(context)
                else
                  output_success(context, updates, opts)
                end

              {{:error, reason}, _, _} ->
                Mix.shell().error("Failed to add note: #{inspect(reason)}")

              {_, {:error, reason}, _} ->
                Mix.shell().error("Failed to add decision: #{inspect(reason)}")

              {_, _, {:error, reason}} ->
                Mix.shell().error("Failed to update: #{inspect(reason)}")
            end

          {:error, :not_found} ->
            Mix.shell().error("Repository '#{repo_id}' not found in portfolio")
        end

      {:error, :not_initialized} ->
        Mix.shell().error("""
        Portfolio not found at #{portfolio_path}
        Run `mix portfolio.init` first.
        """)
    end
  end

  defp build_updates(opts) do
    updates = %{}

    updates =
      if opts[:type],
        do: Map.put(updates, :type, String.to_atom(opts[:type])),
        else: updates

    updates =
      if opts[:status],
        do: Map.put(updates, :status, String.to_atom(opts[:status])),
        else: updates

    updates =
      if opts[:purpose],
        do: Map.put(updates, :purpose, opts[:purpose]),
        else: updates

    updates =
      if opts[:tags],
        do: Map.put(updates, :tags, String.split(opts[:tags], ",")),
        else: updates

    updates =
      if opts[:priority],
        do: Map.put(updates, :priority, String.to_atom(opts[:priority])),
        else: updates

    updates
  end

  defp output_json(context) do
    data = %{
      id: context.repo.id,
      name: context.repo.name,
      type: context.repo.type,
      status: context.repo.status,
      language: context.repo.language,
      purpose: context.repo.purpose,
      tags: context.repo.tags,
      priority: context.repo.priority,
      notes: context.notes,
      decisions: Enum.map(context.decisions, &Map.take(&1, [:id, :title, :date]))
    }

    Mix.shell().info(Jason.encode!(data, pretty: true))
  end

  defp output_success(context, updates, opts) do
    changes = []

    changes =
      if opts[:type], do: changes ++ ["type: #{context.repo.type}"], else: changes

    changes =
      if opts[:status], do: changes ++ ["status: #{context.repo.status}"], else: changes

    changes =
      if opts[:purpose], do: changes ++ ["purpose: #{context.repo.purpose}"], else: changes

    changes =
      if opts[:tags],
        do: changes ++ ["tags: #{Enum.join(context.repo.tags, ", ")}"],
        else: changes

    changes =
      if opts[:priority], do: changes ++ ["priority: #{context.repo.priority}"], else: changes

    changes =
      if opts[:note], do: changes ++ ["note added"], else: changes

    changes =
      if opts[:decision], do: changes ++ ["decision added"], else: changes

    if changes == [] and map_size(updates) == 0 do
      Mix.shell().info("No changes specified. Use --help for available options.")
    else
      Mix.shell().info("""
      #{IO.ANSI.green()}Updated #{context.repo.id}#{IO.ANSI.reset()}

      Changes:
        #{Enum.join(changes, "\n    ")}
      """)
    end
  end

  defp show_help do
    Mix.shell().info("""
    Usage: mix portfolio.edit <id> [options]

    Edit a repository's metadata.

    Options:
      --type, -t      Set repository type
      --status, -s    Set repository status
      --purpose, -p   Set repository purpose
      --tags          Set tags (comma-separated)
      --priority      Set priority (high, medium, low)
      --note          Add a note
      --decision      Add a decision (format: "title:content")
      --json          Output result as JSON
      --help          Show this help message

    Valid types: library, application, port, fork, experiment, template, config, docs
    Valid statuses: active, maintenance, stale, blocked, archived
    Valid priorities: high, medium, low

    Examples:
      mix portfolio.edit my-app --type=library --status=active
      mix portfolio.edit my-app --purpose="Auth library" --tags="auth,security"
      mix portfolio.edit my-app --note="Needs review"
      mix portfolio.edit my-app --decision="Use JWT:After evaluation..."
    """)
  end

  defp default_portfolio_path do
    System.get_env("PORTFOLIO_DIR") || Path.join(System.user_home!(), ".portfolio")
  end
end
