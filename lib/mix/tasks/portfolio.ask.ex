defmodule Mix.Tasks.Portfolio.Ask do
  @moduledoc """
  Ask a natural language question about your portfolio.

  Requires GOOGLE_API_KEY environment variable for Gemini.

  ## Usage

      mix portfolio.ask <question>

  ## Options

    * `--provider` - LLM provider to use (default: gemini)
    * `--json` - Output as JSON
    * `--help` - Show help message

  ## Examples

      mix portfolio.ask "which repos use phoenix?"
      mix portfolio.ask "what are my active elixir libraries?"
      mix portfolio.ask "find repos related to authentication"

  """
  @shortdoc "Ask a question about your portfolio"

  use Mix.Task

  @impl Mix.Task
  def run(args) do
    {opts, query_parts, _} =
      OptionParser.parse(args,
        strict: [
          provider: :string,
          json: :boolean,
          help: :boolean,
          portfolio_dir: :string
        ],
        aliases: [d: :portfolio_dir]
      )

    if opts[:help] do
      show_help()
    else
      question = Enum.join(query_parts, " ")

      if question == "" do
        Mix.shell().error("Missing question. Usage: mix portfolio.ask <question>")
      else
        do_ask(question, opts)
      end
    end
  end

  defp do_ask(question, opts) do
    # Start required apps for HTTP client
    Application.ensure_all_started(:hackney)

    portfolio_path = opts[:portfolio_dir] || default_portfolio_path()

    case PortfolioManager.init(portfolio_path) do
      {:ok, portfolio} ->
        Mix.shell().info("Processing: #{question}")
        Mix.shell().info("")

        provider = parse_provider(opts[:provider])

        case PortfolioManager.query(portfolio, question, provider: provider) do
          {:ok, result} ->
            if opts[:json] do
              output_json(result)
            else
              output_formatted(result)
            end

          {:error, reason} ->
            Mix.shell().error("Query failed: #{format_error(reason)}")
        end

      {:error, :not_initialized} ->
        Mix.shell().error("Portfolio not found. Run `mix portfolio.init` first.")
    end
  end

  defp output_json(result) do
    data = %{
      answer: result.answer,
      tools_used: result.tools_used
    }

    Mix.shell().info(Jason.encode!(data, pretty: true))
  end

  defp output_formatted(result) do
    Mix.shell().info(result.answer)

    if result.tools_used != [] do
      Mix.shell().info("")

      Mix.shell().info(
        "#{IO.ANSI.faint()}Tools used: #{Enum.join(result.tools_used, ", ")}#{IO.ANSI.reset()}"
      )
    end
  end

  defp parse_provider(nil), do: :gemini
  defp parse_provider("gemini"), do: :gemini
  defp parse_provider("claude"), do: :claude
  defp parse_provider(other), do: String.to_atom(other)

  defp format_error(%{message: msg}), do: msg
  defp format_error(reason) when is_binary(reason), do: reason
  defp format_error(reason), do: inspect(reason)

  defp show_help do
    Mix.shell().info("""
    Usage: mix portfolio.ask <question>

    Ask a natural language question about your portfolio.

    Requires GOOGLE_API_KEY environment variable.

    Options:
      --provider     LLM provider (gemini, claude)
      --json         Output as JSON
      --help         Show this help message

    Examples:
      mix portfolio.ask "which repos use phoenix?"
      mix portfolio.ask "what are my stale projects?"
      mix portfolio.ask "find all elixir libraries"
    """)
  end

  defp default_portfolio_path do
    System.get_env("PORTFOLIO_DIR") || Path.join(System.user_home!(), ".portfolio")
  end
end
