defmodule Mix.Tasks.Portfolio.Edit do
  @moduledoc """
  Edit a repository's metadata.

  ## Usage

      mix portfolio.edit <id> [field]

  ## Options

    * `--set` - Set a field directly (e.g. status=stale, computed.commit_count_30d=0)
    * `--editor` - Editor to use (default: $EDITOR)
    * `--type`, `-t` - Set repository type (legacy)
    * `--status`, `-s` - Set repository status (legacy)
    * `--purpose`, `-p` - Set repository purpose (legacy)
    * `--tags` - Set tags (comma-separated, legacy)
    * `--priority` - Set priority (high, medium, low, legacy)
    * `--note` - Add a note (legacy)
    * `--decision` - Add a decision (format: "title:content", legacy)
    * `--json` - Output result as JSON
    * `--help` - Show help message

  ## Valid Types

    library, application, service, port, fork, experiment, template, config, docs, monorepo, archive

  ## Valid Statuses

    active, maintenance, stale, blocked, archived

  ## Examples

      mix portfolio.edit my-app
      mix portfolio.edit my-app notes
      mix portfolio.edit my-app --set status=stale
      mix portfolio.edit my-app --set computed.commit_count_30d=0
      mix portfolio.edit my-app --type=library
      mix portfolio.edit my-app --note="Needs review before next release"

  """
  @shortdoc "Edit a repository's metadata"

  use Mix.Task

  alias PortfolioManager.CLI.Exit

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
          set: :keep,
          editor: :string,
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
        [repo_id | rest] ->
          edit_repo(repo_id, List.first(rest), opts)

        [] ->
          Mix.shell().error("Error: Repository ID is required")
          show_help()
          Exit.halt(:invalid_args)
      end
    end
  end

  defp edit_repo(repo_id, field, opts) do
    portfolio_path = opts[:portfolio_dir] || default_portfolio_path()

    case PortfolioManager.init(portfolio_path) do
      {:ok, portfolio} ->
        case PortfolioManager.get_repo(portfolio, repo_id) do
          {:ok, _repo} ->
            updates = build_updates(opts)
            set_updates = opts[:set] |> List.wrap()

            has_updates =
              map_size(updates) > 0 or set_updates != [] or opts[:note] or opts[:decision]

            cond do
              has_updates ->
                handle_updates(portfolio, repo_id, updates, set_updates, opts)

              true ->
                open_edit_target(portfolio, repo_id, field, opts)
            end

          {:error, :not_found} ->
            Mix.shell().error("Repository '#{repo_id}' not found in portfolio")
            Exit.halt(:not_found)
        end

      {:error, :not_initialized} ->
        Mix.shell().error("""
        Portfolio not found at #{portfolio_path}
        Run `mix portfolio.init` first.
        """)

        Exit.halt(:config)
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

  defp handle_updates(portfolio, repo_id, updates, set_updates, opts) do
    note_result =
      if opts[:note] do
        PortfolioManager.add_note(portfolio, repo_id, opts[:note])
      else
        {:ok, nil}
      end

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

    context_result =
      case set_updates do
        [] ->
          if map_size(updates) > 0 do
            PortfolioManager.update_context(portfolio, repo_id, updates)
          else
            PortfolioManager.get_context(portfolio, repo_id)
          end

        _ ->
          with {:ok, context} <- PortfolioManager.get_context(portfolio, repo_id) do
            merged_updates = apply_set_updates(context, updates, set_updates)

            if map_size(merged_updates) > 0 do
              PortfolioManager.update_context(portfolio, repo_id, merged_updates)
            else
              {:ok, context}
            end
          end
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
        Exit.halt(:error)

      {_, {:error, reason}, _} ->
        Mix.shell().error("Failed to add decision: #{inspect(reason)}")
        Exit.halt(:error)

      {_, _, {:error, reason}} ->
        Mix.shell().error("Failed to update: #{inspect(reason)}")
        Exit.halt(:error)
    end
  end

  defp apply_set_updates(context, updates, set_updates) do
    Enum.reduce(set_updates, updates, fn set_expr, acc ->
      case parse_set(set_expr) do
        {:ok, {key, value}} ->
          put_set_value(acc, context, key, value)

        {:error, _} ->
          acc
      end
    end)
  end

  defp parse_set(expr) do
    case String.split(expr, "=", parts: 2) do
      [key, value] -> {:ok, {String.trim(key), String.trim(value)}}
      _ -> {:error, :invalid_set}
    end
  end

  defp put_set_value(acc, context, "computed." <> rest, value) do
    computed = Map.get(acc, :computed) || context.computed || %{}
    new_computed = put_nested(computed, String.split(rest, "."), parse_scalar(value))
    Map.put(acc, :computed, new_computed)
  end

  defp put_set_value(acc, context, "port." <> rest, value) do
    port = Map.get(acc, :port) || context.repo.port || %{}
    new_port = put_nested(port, String.split(rest, "."), parse_scalar(value))
    Map.put(acc, :port, new_port)
  end

  defp put_set_value(acc, _context, "tags", value) do
    tags =
      value
      |> String.split(",", trim: true)
      |> Enum.map(&String.trim/1)

    Map.put(acc, :tags, tags)
  end

  defp put_set_value(acc, _context, key, value) do
    cast_value =
      case key do
        "status" -> String.to_atom(value)
        "type" -> String.to_atom(value)
        "language" -> String.to_atom(value)
        "priority" -> String.to_atom(value)
        _ -> parse_scalar(value)
      end

    Map.put(acc, String.to_atom(key), cast_value)
  end

  defp put_nested(_map, [], value), do: value

  defp put_nested(map, [key], value) when is_map(map) do
    Map.put(map, key, value)
  end

  defp put_nested(map, [key | rest], value) when is_map(map) do
    existing = Map.get(map, key) || %{}
    Map.put(map, key, put_nested(existing, rest, value))
  end

  defp parse_scalar("true"), do: true
  defp parse_scalar("false"), do: false
  defp parse_scalar("null"), do: nil
  defp parse_scalar("nil"), do: nil

  defp parse_scalar(value) do
    case Integer.parse(value) do
      {int, ""} -> int
      _ -> value
    end
  end

  defp open_edit_target(portfolio, repo_id, field, opts) do
    editor = opts[:editor] || System.get_env("EDITOR") || "vi"
    base_path = PortfolioManager.Portfolio.get_storage_state(portfolio).path

    {path, label} = edit_target(repo_id, field)
    full_path = Path.join(base_path, path)

    if String.ends_with?(full_path, [".yml", ".md"]) do
      File.mkdir_p!(Path.dirname(full_path))

      if not File.exists?(full_path) do
        File.write!(full_path, "")
      end
    else
      File.mkdir_p!(full_path)
    end

    case System.find_executable(editor) do
      nil ->
        Mix.shell().error("Editor not found: #{editor}")

      _ ->
        Mix.shell().info("Opening #{label} for #{repo_id} with #{editor}...")
        System.cmd(editor, [full_path], into: IO.stream(:stdio, :line))
    end
  end

  defp edit_target(repo_id, nil),
    do: {Path.join(["repos", repo_id, "context.yml"]), "context"}

  defp edit_target(repo_id, "context"),
    do: {Path.join(["repos", repo_id, "context.yml"]), "context"}

  defp edit_target(repo_id, "notes"),
    do: {Path.join(["repos", repo_id, "notes.md"]), "notes"}

  defp edit_target(repo_id, "decisions"),
    do: {Path.join(["repos", repo_id, "decisions"]), "decisions"}

  defp edit_target(repo_id, _field),
    do: {Path.join(["repos", repo_id, "context.yml"]), "context"}

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

    set_updates = opts[:set] |> List.wrap()

    changes =
      if set_updates != [],
        do: changes ++ Enum.map(set_updates, &"set #{&1}"),
        else: changes

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
    Usage: mix portfolio.edit <id> [field] [options]

    Edit a repository's metadata.

    Options:
      --set           Set a field directly (repeatable)
      --editor        Editor to use (default: $EDITOR)
      --type, -t      Set repository type (legacy)
      --status, -s    Set repository status (legacy)
      --purpose, -p   Set repository purpose (legacy)
      --tags          Set tags (comma-separated, legacy)
      --priority      Set priority (high, medium, low, legacy)
      --note          Add a note (legacy)
      --decision      Add a decision (format: "title:content", legacy)
      --json          Output result as JSON
      --help          Show this help message

    Valid types: library, application, service, port, fork, experiment, template, config, docs, monorepo, archive
    Valid statuses: active, maintenance, stale, blocked, archived
    Valid priorities: high, medium, low

    Examples:
      mix portfolio.edit my-app
      mix portfolio.edit my-app notes
      mix portfolio.edit my-app --set status=stale
      mix portfolio.edit my-app --set computed.commit_count_30d=0
      mix portfolio.edit my-app --type=library --status=active
      mix portfolio.edit my-app --note="Needs review"
    """)
  end

  defp default_portfolio_path do
    System.get_env("PORTFOLIO_DIR") || Path.join(System.user_home!(), "portfolio")
  end
end
