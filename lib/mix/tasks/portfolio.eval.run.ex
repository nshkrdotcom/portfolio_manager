defmodule Mix.Tasks.Portfolio.Eval.Run do
  @moduledoc """
  Run evaluation against test cases.

  ## Usage

      mix portfolio.eval.run

  ## Options

  - `--mode` - Search mode: semantic, fulltext, hybrid (default: semantic)
  - `--collection` - Only evaluate test cases for this collection
  - `--generate` - Generate test cases if none exist
  - `--format` - Output format: table, json (default: table)
  - `--fail-under` - Exit with code 1 if recall@5 below threshold
  - `--help` - Show this help message
  """

  use Mix.Task

  # Dialyzer struggles with cross-project Ecto changeset type inference
  @dialyzer {:nowarn_function, run_evaluation: 1}
  @dialyzer {:nowarn_function, do_generate: 2}
  @dialyzer {:nowarn_function, persist_test_cases: 2}
  @dialyzer {:nowarn_function, persist_test_case: 2}
  @dialyzer {:nowarn_function, count_test_cases: 2}

  alias PortfolioIndex.Evaluation
  alias PortfolioIndex.Evaluation.Generator
  alias PortfolioIndex.Schemas.TestCase

  @shortdoc "Run retrieval evaluation"

  @impl Mix.Task
  def run(args) do
    {opts, _args, _} = parse_args(args)

    if opts[:help] do
      print_help()
    else
      run_evaluation(opts)
    end
  end

  @doc false
  def parse_args(args) do
    OptionParser.parse(args,
      strict: [
        mode: :string,
        collection: :string,
        generate: :boolean,
        sample_size: :integer,
        format: :string,
        fail_under: :float,
        help: :boolean
      ]
    )
  end

  @doc false
  def parse_mode(nil), do: :semantic
  def parse_mode("semantic"), do: :semantic
  def parse_mode("fulltext"), do: :fulltext
  def parse_mode("hybrid"), do: :hybrid
  def parse_mode(other), do: raise("Invalid mode: #{other}")

  @doc false
  def format_percentage(value) when is_float(value) do
    "#{Float.round(value * 100, 1)}%"
  end

  @doc false
  def check_threshold(_metrics, nil), do: :ok

  def check_threshold(metrics, threshold) do
    recall_at_k = metrics[:recall_at_k] || metrics["recall_at_k"] || %{}
    recall_at_5 = recall_at_k[5] || recall_at_k["5"] || 0.0

    if recall_at_5 >= threshold, do: :ok, else: :fail
  end

  defp run_evaluation(opts) do
    Mix.Task.run("app.start")

    repo = get_repo()
    mode = parse_mode(opts[:mode])
    format = opts[:format] || "table"
    threshold = opts[:fail_under]
    collection = opts[:collection]

    maybe_generate(repo, opts)

    Mix.shell().info("Running evaluation in #{mode} mode...")

    search_fn = build_search_fn(mode)

    run_opts = [
      mode: mode,
      collection: collection,
      search_fn: search_fn
    ]

    case Evaluation.run(repo, run_opts) do
      {:ok, run} ->
        print_results(run, format)
        handle_threshold(run.aggregate_metrics, threshold)

      {:error, :no_test_cases} ->
        Mix.shell().error("No test cases found. Run with --generate first.")
        exit({:shutdown, 1})

      {:error, :search_fn_required} ->
        Mix.shell().error("Search function not available. Check configuration.")
        exit({:shutdown, 1})

      {:error, reason} ->
        Mix.shell().error("Evaluation failed: #{inspect(reason)}")
        exit({:shutdown, 1})
    end
  end

  defp maybe_generate(repo, opts) do
    if opts[:generate], do: maybe_generate_if_empty(repo, opts), else: :skip
  end

  defp maybe_generate_if_empty(repo, opts) do
    count = count_test_cases(repo, opts[:collection])
    if count > 0, do: :skip, else: do_generate(repo, opts)
  end

  defp do_generate(repo, opts) do
    sample_size = opts[:sample_size] || 10
    Mix.shell().info("No test cases found. Generating #{sample_size}...")

    llm = get_llm()

    generator_opts =
      [llm: llm, sample_size: sample_size]
      |> maybe_add(:collection, opts[:collection])

    case Generator.generate(repo, generator_opts) do
      {:ok, test_cases} ->
        saved = persist_test_cases(repo, test_cases)
        Mix.shell().info("Generated #{saved} test cases")

      {:error, reason} ->
        Mix.shell().error("Generation failed: #{inspect(reason)}")
        exit({:shutdown, 1})
    end
  end

  defp count_test_cases(repo, nil) do
    import Ecto.Query
    repo.aggregate(TestCase, :count)
  end

  defp count_test_cases(repo, collection) do
    import Ecto.Query
    repo.aggregate(from(tc in TestCase, where: tc.collection == ^collection), :count)
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

  defp print_results(run, "json") do
    result = %{
      status: run.status,
      metrics: run.aggregate_metrics,
      config: run.config,
      started_at: run.started_at,
      completed_at: run.completed_at
    }

    json = Jason.encode!(result, pretty: true)
    Mix.shell().info(json)
  end

  defp print_results(run, _format) do
    m = run.aggregate_metrics

    recall = get_metric_map(m, :recall_at_k)
    precision = get_metric_map(m, :precision_at_k)
    hit_rate = get_metric_map(m, :hit_rate_at_k)
    mrr = get_metric(m, :mrr, 0.0)

    Mix.shell().info("""

    #{String.duplicate("=", 42)}
             Evaluation Results
    #{String.duplicate("=", 42)}
      Recall@1:     #{format_pct(get_at_k(recall, 1))}
      Recall@3:     #{format_pct(get_at_k(recall, 3))}
      Recall@5:     #{format_pct(get_at_k(recall, 5))}
      Recall@10:    #{format_pct(get_at_k(recall, 10))}
    #{String.duplicate("-", 42)}
      Precision@1:  #{format_pct(get_at_k(precision, 1))}
      Precision@5:  #{format_pct(get_at_k(precision, 5))}
    #{String.duplicate("-", 42)}
      MRR:          #{format_pct(mrr)}
      Hit Rate@5:   #{format_pct(get_at_k(hit_rate, 5))}
    #{String.duplicate("=", 42)}
    """)
  end

  defp format_pct(nil), do: "N/A"

  defp format_pct(value) when is_float(value) do
    "#{Float.round(value * 100, 1)}%"
    |> String.pad_leading(8)
  end

  defp handle_threshold(_metrics, nil), do: :ok

  defp handle_threshold(metrics, threshold) do
    case check_threshold(metrics, threshold) do
      :ok ->
        Mix.shell().info("Recall@5 meets threshold (#{threshold * 100}%)")

      :fail ->
        recall_at_k = metrics[:recall_at_k] || metrics["recall_at_k"] || %{}
        recall_at_5 = recall_at_k[5] || recall_at_k["5"] || 0.0

        Mix.shell().error(
          "Recall@5 (#{Float.round(recall_at_5 * 100, 1)}%) below threshold (#{threshold * 100}%)"
        )

        exit({:shutdown, 1})
    end
  end

  defp print_help do
    Mix.shell().info("""
    Run evaluation against test cases.

    Usage:
      mix portfolio.eval.run [options]

    Options:
      --mode          Search mode: semantic, fulltext, hybrid (default: semantic)
      --collection    Only evaluate test cases for this collection
      --generate      Generate test cases if none exist
      --sample-size   Number of test cases to generate (default: 10)
      --format        Output format: table, json (default: table)
      --fail-under    Exit with code 1 if recall@5 below threshold (e.g., 0.8)
      --help          Show this help message

    Examples:
      mix portfolio.eval.run
      mix portfolio.eval.run --mode hybrid
      mix portfolio.eval.run --generate --sample-size 50
      mix portfolio.eval.run --format json > results.json
      mix portfolio.eval.run --fail-under 0.8
    """)
  end

  defp build_search_fn(mode) do
    fn question, opts ->
      search_mode = Keyword.get(opts, :mode, mode)
      limit = 10

      case Application.get_env(:portfolio_manager, :search_adapter) do
        nil ->
          # Default: use RAG module
          PortfolioManager.RAG.search(question, mode: search_mode, limit: limit)

        adapter when is_atom(adapter) ->
          adapter.search(question, mode: search_mode, limit: limit)
      end
    end
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
    case PortfolioManager.LLM.complete([%{role: :user, content: prompt}], []) do
      {:ok, %{content: content}} -> {:ok, content}
      {:error, _} = err -> err
    end
  end

  defp maybe_add(opts, _key, nil), do: opts
  defp maybe_add(opts, key, value), do: Keyword.put(opts, key, value)

  # Metrics helper functions to reduce complexity
  defp get_metric(metrics, key, default) do
    metrics[key] || metrics[Atom.to_string(key)] || default
  end

  defp get_metric_map(metrics, key) do
    metrics[key] || metrics[Atom.to_string(key)] || %{}
  end

  defp get_at_k(map, k) do
    map[k] || map[to_string(k)]
  end
end
