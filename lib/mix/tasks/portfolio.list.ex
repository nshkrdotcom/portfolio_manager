defmodule Mix.Tasks.Portfolio.List do
  @moduledoc """
  List tracked repositories in the portfolio.

  ## Usage

      mix portfolio.list [options]

  ## Options

    * `--status`, `-s` - Filter by status (active, stale, archived, etc.)
    * `--type`, `-t` - Filter by type (library, application, port, etc.)
    * `--language`, `-l` - Filter by language (elixir, python, etc.)
    * `--json` - Output as JSON
    * `--help` - Show help message

  ## Examples

      mix portfolio.list
      mix portfolio.list --status=active
      mix portfolio.list --type=library --language=elixir
      mix portfolio.list --json

  """
  @shortdoc "List tracked repositories"

  use Mix.Task

  @impl Mix.Task
  def run(args) do
    {opts, _args, _} =
      OptionParser.parse(args,
        strict: [
          status: :string,
          type: :string,
          language: :string,
          json: :boolean,
          help: :boolean,
          portfolio_dir: :string
        ],
        aliases: [s: :status, t: :type, l: :language, d: :portfolio_dir]
      )

    if opts[:help] do
      show_help()
    else
      portfolio_path = opts[:portfolio_dir] || default_portfolio_path()

      case PortfolioManager.init(portfolio_path) do
        {:ok, portfolio} ->
          repos = PortfolioManager.list_repos(portfolio)
          filtered = filter_repos(repos, opts)

          if opts[:json] do
            output_json(filtered)
          else
            output_table(filtered)
          end

        {:error, :not_initialized} ->
          Mix.shell().error("""
          Portfolio not found at #{portfolio_path}
          Run `mix portfolio.init` first.
          """)
      end
    end
  end

  defp filter_repos(repos, opts) do
    repos
    |> filter_by(:status, opts[:status])
    |> filter_by(:type, opts[:type])
    |> filter_by(:language, opts[:language])
  end

  defp filter_by(repos, _field, nil), do: repos

  defp filter_by(repos, field, value) do
    atom_value = String.to_atom(value)

    Enum.filter(repos, fn repo ->
      Map.get(repo, field) == atom_value
    end)
  end

  defp output_json(repos) do
    data =
      Enum.map(repos, fn repo ->
        %{
          id: repo.id,
          name: repo.name,
          type: repo.type,
          status: repo.status,
          language: repo.language,
          path: repo.path
        }
      end)

    Mix.shell().info(Jason.encode!(data, pretty: true))
  end

  defp output_table(repos) do
    if Enum.empty?(repos) do
      Mix.shell().info("No repositories found.")
    else
      # Header
      Mix.shell().info(
        String.pad_trailing("ID", 25) <>
          String.pad_trailing("TYPE", 12) <>
          String.pad_trailing("STATUS", 12) <>
          String.pad_trailing("LANGUAGE", 12)
      )

      Mix.shell().info(String.duplicate("─", 61))

      # Rows
      Enum.each(repos, fn repo ->
        Mix.shell().info(
          String.pad_trailing(to_string(repo.id), 25) <>
            String.pad_trailing(to_string(repo.type), 12) <>
            String.pad_trailing(to_string(repo.status), 12) <>
            String.pad_trailing(to_string(repo.language), 12)
        )
      end)

      Mix.shell().info("")
      Mix.shell().info("Total: #{length(repos)} repos")
    end
  end

  defp show_help do
    Mix.shell().info("""
    Usage: mix portfolio.list [options]

    List tracked repositories in the portfolio.

    Options:
      --status, -s     Filter by status (active, stale, archived)
      --type, -t       Filter by type (library, application, port)
      --language, -l   Filter by language (elixir, python, javascript)
      --json           Output as JSON
      --help           Show this help message

    Examples:
      mix portfolio.list
      mix portfolio.list --status=active --type=library
      mix portfolio.list --json
    """)
  end

  defp default_portfolio_path do
    System.get_env("PORTFOLIO_DIR") || Path.join(System.user_home!(), ".portfolio")
  end
end
