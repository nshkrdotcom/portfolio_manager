defmodule Mix.Tasks.Portfolio.Eval.Generate do
  @moduledoc """
  Generate synthetic test cases from document chunks.

  ## Usage

      mix portfolio.eval.generate

  ## Options

  - `--sample-size` - Number of chunks to sample (default: 10)
  - `--collection` - Only sample from this collection
  - `--source-id` - Only sample from documents with this source ID
  - `--help` - Show this help message
  """

  use Mix.Task

  # Dialyzer struggles with cross-project Ecto changeset type inference
  @dialyzer {:nowarn_function, run_generate: 1}
  @dialyzer {:nowarn_function, persist_test_cases: 2}
  @dialyzer {:nowarn_function, persist_test_case: 2}

  alias PortfolioIndex.Evaluation.Generator
  alias PortfolioIndex.Schemas.TestCase

  @shortdoc "Generate synthetic evaluation test cases"

  @impl Mix.Task
  def run(args) do
    {opts, _args, _} = parse_args(args)

    if opts[:help] do
      print_help()
    else
      run_generate(opts)
    end
  end

  @doc false
  def parse_args(args) do
    OptionParser.parse(args,
      strict: [
        sample_size: :integer,
        collection: :string,
        source_id: :string,
        help: :boolean
      ]
    )
  end

  @doc false
  def build_generator_opts(parsed) do
    [:sample_size, :collection, :source_id]
    |> Enum.reduce([], fn key, acc ->
      case Keyword.get(parsed, key) do
        nil -> acc
        value -> Keyword.put(acc, key, value)
      end
    end)
  end

  defp run_generate(opts) do
    Mix.Task.run("app.start")

    repo = get_repo()
    llm = get_llm()

    sample_size = Keyword.get(opts, :sample_size, 10)

    Mix.shell().info("Generating test cases from #{sample_size} chunks...")

    generator_opts =
      opts
      |> build_generator_opts()
      |> Keyword.put(:llm, llm)
      |> Keyword.put_new(:sample_size, sample_size)

    case Generator.generate(repo, generator_opts) do
      {:ok, test_cases} ->
        # Persist the test cases
        saved_count = persist_test_cases(repo, test_cases)
        Mix.shell().info("Generated and saved #{saved_count} test cases")

      {:error, :llm_required} ->
        Mix.shell().error("Error: LLM not configured. Set :portfolio_manager, :llm config")
        exit({:shutdown, 1})

      {:error, reason} ->
        Mix.shell().error("Failed: #{inspect(reason)}")
        exit({:shutdown, 1})
    end
  end

  defp persist_test_cases(repo, test_cases) do
    Enum.reduce(test_cases, 0, fn test_case, count ->
      case persist_test_case(repo, test_case) do
        {:ok, _} -> count + 1
        {:error, _} -> count
      end
    end)
  end

  defp persist_test_case(repo, test_case) do
    %TestCase{}
    |> TestCase.changeset(%{
      question: test_case.question,
      source: test_case.source,
      collection: test_case.collection,
      metadata: test_case.metadata
    })
    |> repo.insert()
  end

  defp print_help do
    Mix.shell().info("""
    Generate synthetic test cases from document chunks.

    Usage:
      mix portfolio.eval.generate [options]

    Options:
      --sample-size    Number of chunks to sample (default: 10)
      --collection     Only sample from this collection
      --source-id      Only sample from documents with this source ID
      --help           Show this help message

    Examples:
      mix portfolio.eval.generate
      mix portfolio.eval.generate --sample-size 50
      mix portfolio.eval.generate --collection my-docs --sample-size 100
    """)
  end

  defp get_repo do
    Application.get_env(:portfolio_manager, :repo, PortfolioManager.Repo)
  end

  defp get_llm do
    case Application.get_env(:portfolio_manager, :llm) do
      nil -> &default_llm_fn/1
      llm_fn when is_function(llm_fn, 1) -> llm_fn
      _other -> nil
    end
  end

  defp default_llm_fn(prompt) do
    alias PortfolioManager.Router

    case Router.complete([%{role: :user, content: prompt}], []) do
      {:ok, %{content: content}} -> {:ok, content}
      {:error, _} = err -> err
    end
  end
end
