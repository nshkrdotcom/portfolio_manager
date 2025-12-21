defmodule Mix.Tasks.Portfolio.Repl do
  @moduledoc """
  Start an interactive portfolio session.

  ## Usage

      mix portfolio.repl

  ## Commands

  Within the REPL, you can use these commands:

    * `list [--status=active]` - List repositories
    * `show <id>` - Show repository details
    * `search <query>` - Search repositories
    * `ask <question>` - Ask questions (requires RAG)
    * `edit <id> <field>=<value>` - Edit repository
    * `sync` - Synchronize portfolio
    * `status` - Show portfolio status
    * `help` - Show available commands
    * `exit` or `quit` - Exit REPL

  ## Examples

      portfolio> list
      portfolio> list --status=active
      portfolio> show my-app
      portfolio> search authentication
      portfolio> ask "which repos are stale?"
      portfolio> edit my-app status=active
      portfolio> exit

  """
  @shortdoc "Start interactive portfolio session"

  use Mix.Task

  @impl Mix.Task
  def run(args) do
    {opts, _args, _} =
      OptionParser.parse(args,
        strict: [
          help: :boolean,
          portfolio_dir: :string
        ],
        aliases: [d: :portfolio_dir]
      )

    if opts[:help] do
      show_help()
    else
      start_repl(opts)
    end
  end

  defp start_repl(opts) do
    portfolio_path = opts[:portfolio_dir] || default_portfolio_path()

    case PortfolioManager.init(portfolio_path) do
      {:ok, portfolio} ->
        IO.puts("""
        #{IO.ANSI.cyan()}Portfolio Manager Interactive Mode#{IO.ANSI.reset()}
        Type 'help' for available commands, 'exit' to quit.
        """)

        loop(portfolio)

      {:error, :not_initialized} ->
        Mix.shell().error("""
        Portfolio not found at #{portfolio_path}
        Run `mix portfolio.init` first.
        """)
    end
  end

  defp loop(portfolio) do
    prompt = "#{IO.ANSI.green()}portfolio>#{IO.ANSI.reset()} "

    case IO.gets(prompt) do
      :eof ->
        IO.puts("\nGoodbye!")

      input when is_binary(input) ->
        input = String.trim(input)

        case handle_input(input, portfolio) do
          :exit ->
            IO.puts("Goodbye!")

          :continue ->
            loop(portfolio)
        end
    end
  end

  defp handle_input("", _portfolio), do: :continue
  defp handle_input("exit", _portfolio), do: :exit
  defp handle_input("quit", _portfolio), do: :exit
  defp handle_input("q", _portfolio), do: :exit

  defp handle_input("help", _portfolio) do
    IO.puts("""

    #{IO.ANSI.cyan()}Available Commands#{IO.ANSI.reset()}

    #{IO.ANSI.yellow()}list#{IO.ANSI.reset()} [options]        List repositories
      --status=<status>     Filter by status
      --type=<type>         Filter by type
      --language=<lang>     Filter by language

    #{IO.ANSI.yellow()}show#{IO.ANSI.reset()} <id>             Show repository details

    #{IO.ANSI.yellow()}search#{IO.ANSI.reset()} <query>        Search repositories

    #{IO.ANSI.yellow()}ask#{IO.ANSI.reset()} <question>        Ask questions (requires RAG)

    #{IO.ANSI.yellow()}edit#{IO.ANSI.reset()} <id> <field>=<value>
                          Edit repository metadata
                          Fields: status, type, purpose, tags, priority

    #{IO.ANSI.yellow()}sync#{IO.ANSI.reset()}                  Synchronize portfolio

    #{IO.ANSI.yellow()}status#{IO.ANSI.reset()}                Show portfolio statistics

    #{IO.ANSI.yellow()}graph#{IO.ANSI.reset()} [id]            Show relationship graph

    #{IO.ANSI.yellow()}help#{IO.ANSI.reset()}                  Show this help

    #{IO.ANSI.yellow()}exit#{IO.ANSI.reset()}, #{IO.ANSI.yellow()}quit#{IO.ANSI.reset()}, #{IO.ANSI.yellow()}q#{IO.ANSI.reset()}        Exit REPL
    """)

    :continue
  end

  defp handle_input("list" <> rest, portfolio) do
    args = parse_args(String.trim(rest))
    repos = PortfolioManager.list_repos(portfolio)
    filtered = apply_filters(repos, args)
    print_repos(filtered)
    :continue
  end

  defp handle_input("show " <> id, portfolio) do
    id = String.trim(id)

    case PortfolioManager.get_context(portfolio, id) do
      {:ok, context} ->
        print_context(context)

      {:error, :not_found} ->
        IO.puts("#{IO.ANSI.red()}Repository '#{id}' not found#{IO.ANSI.reset()}")
    end

    :continue
  end

  defp handle_input("search " <> query, portfolio) do
    query = String.trim(query)
    results = PortfolioManager.search(portfolio, query)

    if Enum.empty?(results) do
      IO.puts("No results found for '#{query}'")
    else
      IO.puts("\nFound #{length(results)} results:\n")
      print_repos(results)
    end

    :continue
  end

  defp handle_input("ask " <> question, portfolio) do
    question = String.trim(question)
    IO.puts("\n#{IO.ANSI.yellow()}Thinking...#{IO.ANSI.reset()}")

    case PortfolioManager.query(portfolio, question) do
      {:ok, result} ->
        IO.puts("\n#{result.answer}\n")

      {:error, reason} ->
        IO.puts("#{IO.ANSI.red()}Error: #{inspect(reason)}#{IO.ANSI.reset()}")
    end

    :continue
  end

  defp handle_input("edit " <> rest, portfolio) do
    case String.split(String.trim(rest), " ", parts: 2) do
      [id, updates_str] ->
        updates = parse_updates(updates_str)

        case PortfolioManager.update_context(portfolio, id, updates) do
          {:ok, context} ->
            PortfolioManager.sync(portfolio)
            IO.puts("#{IO.ANSI.green()}Updated #{context.repo.id}#{IO.ANSI.reset()}")

          {:error, reason} ->
            IO.puts("#{IO.ANSI.red()}Error: #{inspect(reason)}#{IO.ANSI.reset()}")
        end

      _ ->
        IO.puts("Usage: edit <id> <field>=<value>")
    end

    :continue
  end

  defp handle_input("sync", portfolio) do
    case PortfolioManager.sync(portfolio) do
      :ok -> IO.puts("#{IO.ANSI.green()}Portfolio synchronized#{IO.ANSI.reset()}")
      {:error, reason} -> IO.puts("#{IO.ANSI.red()}Error: #{inspect(reason)}#{IO.ANSI.reset()}")
    end

    :continue
  end

  defp handle_input("status", portfolio) do
    stats = PortfolioManager.status(portfolio)
    print_status(stats)
    :continue
  end

  defp handle_input("graph" <> rest, portfolio) do
    graph = PortfolioManager.Graph.build(portfolio)
    root = String.trim(rest)

    opts = if root != "", do: [root: root], else: []
    ascii = PortfolioManager.Graph.to_ascii(graph, opts)

    IO.puts("\n#{ascii}\n")
    :continue
  end

  defp handle_input(input, _portfolio) do
    IO.puts("Unknown command: #{input}")
    IO.puts("Type 'help' for available commands.")
    :continue
  end

  defp parse_args(str) do
    str
    |> String.split()
    |> Enum.reduce(%{}, fn arg, acc ->
      case String.split(arg, "=", parts: 2) do
        ["--" <> key, value] ->
          Map.put(acc, String.to_atom(key), value)

        ["-" <> key, value] ->
          Map.put(acc, String.to_atom(key), value)

        _ ->
          acc
      end
    end)
  end

  defp parse_updates(str) do
    str
    |> String.split()
    |> Enum.reduce(%{}, fn part, acc ->
      case String.split(part, "=", parts: 2) do
        [key, value] ->
          atom_key = String.to_atom(key)

          parsed_value =
            cond do
              key in ~w(status type priority) -> String.to_atom(value)
              key == "tags" -> String.split(value, ",")
              true -> value
            end

          Map.put(acc, atom_key, parsed_value)

        _ ->
          acc
      end
    end)
  end

  defp apply_filters(repos, args) do
    repos
    |> filter_by(args, :status)
    |> filter_by(args, :type)
    |> filter_by(args, :language)
  end

  defp filter_by(repos, args, field) do
    case Map.get(args, field) do
      nil ->
        repos

      value ->
        atom_value = String.to_atom(value)
        Enum.filter(repos, &(Map.get(&1, field) == atom_value))
    end
  end

  defp print_repos(repos) do
    if Enum.empty?(repos) do
      IO.puts("No repositories found.")
    else
      IO.puts("")

      IO.puts(
        String.pad_trailing("ID", 25) <>
          String.pad_trailing("TYPE", 12) <>
          String.pad_trailing("STATUS", 12) <>
          String.pad_trailing("LANGUAGE", 12)
      )

      IO.puts(String.duplicate("─", 61))

      Enum.each(repos, fn repo ->
        IO.puts(
          String.pad_trailing(to_string(repo.id), 25) <>
            String.pad_trailing(to_string(repo.type), 12) <>
            String.pad_trailing(to_string(repo.status), 12) <>
            String.pad_trailing(to_string(repo.language), 12)
        )
      end)

      IO.puts("")
      IO.puts("Total: #{length(repos)} repos")
      IO.puts("")
    end
  end

  defp print_context(context) do
    repo = context.repo

    IO.puts("""

    #{IO.ANSI.cyan()}#{repo.name}#{IO.ANSI.reset()} (#{repo.id})
    ──────────────────────────────

    Type:     #{repo.type}
    Status:   #{repo.status}
    Language: #{repo.language}
    Path:     #{repo.path}
    #{if repo.purpose, do: "Purpose:  #{repo.purpose}", else: ""}
    #{if repo.tags != [], do: "Tags:     #{Enum.join(repo.tags, ", ")}", else: ""}
    #{if repo.priority, do: "Priority: #{repo.priority}", else: ""}
    """)

    if context.notes do
      IO.puts("Notes:")
      IO.puts("  #{String.slice(context.notes, 0, 200)}...")
    end

    if context.decisions != [] do
      IO.puts("\nDecisions: #{length(context.decisions)}")

      Enum.take(context.decisions, 3)
      |> Enum.each(fn d ->
        IO.puts("  - #{d.title}")
      end)
    end

    IO.puts("")
  end

  defp print_status(stats) do
    IO.puts("""

    #{IO.ANSI.cyan()}Portfolio Status#{IO.ANSI.reset()}
    ─────────────────

    Total repositories: #{stats.total}
    Relationships:      #{stats.relationships}

    By Status:
    #{format_counts(stats.by_status)}

    By Type:
    #{format_counts(stats.by_type)}

    By Language:
    #{format_counts(stats.by_language)}
    """)
  end

  defp format_counts(map) do
    map
    |> Enum.sort_by(fn {_k, v} -> -v end)
    |> Enum.map(fn {k, v} -> "  #{String.pad_trailing(to_string(k), 15)} #{v}" end)
    |> Enum.join("\n")
  end

  defp show_help do
    Mix.shell().info("""
    Usage: mix portfolio.repl [options]

    Start an interactive portfolio session.

    Options:
      --portfolio-dir, -d   Portfolio directory path
      --help                Show this help message

    Within the REPL, use 'help' to see available commands.
    """)
  end

  defp default_portfolio_path do
    System.get_env("PORTFOLIO_DIR") || Path.join(System.user_home!(), ".portfolio")
  end
end
