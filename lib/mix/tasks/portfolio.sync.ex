defmodule Mix.Tasks.Portfolio.Sync do
  @dialyzer {:nowarn_function,
             [
               output_json: 1,
               output_success: 2,
               output_repo_json: 1,
               output_repo_success: 1,
               show_help: 0,
               refresh_repo_info: 3,
               handle_sync_portfolio: 2,
               handle_sync_repo: 3
             ]}

  @moduledoc """
  Synchronize portfolio state with storage and refresh repository information.

  ## Usage

      mix portfolio.sync [id]

  ## Options

    * `--full` - Full rescan including agentic detection
    * `--computed-only` - Only update computed fields
    * `--check-remotes` - Fetch remotes and update remote stats
    * `--views` - Regenerate computed views (legacy)
    * `--json` - Output result as JSON
    * `--help` - Show help message

  ## Examples

      # Sync portfolio state to storage
      mix portfolio.sync

      # Refresh a specific repository
      mix portfolio.sync my-app

      # Full rescan with agentic detection
      mix portfolio.sync --full

      # Only update computed fields
      mix portfolio.sync --computed-only

  """
  @shortdoc "Synchronize portfolio state"

  use Mix.Task

  alias PortfolioManager.Adapters.{FileDetector, LocalGit}
  alias PortfolioManager.CLI.Exit
  alias PortfolioManager.Detection.Agentic

  @impl Mix.Task
  def run(args) do
    {opts, args, _} =
      OptionParser.parse(args,
        strict: [
          full: :boolean,
          computed_only: :boolean,
          check_remotes: :boolean,
          all: :boolean,
          views: :boolean,
          json: :boolean,
          help: :boolean,
          portfolio_dir: :string
        ],
        aliases: [d: :portfolio_dir]
      )

    if opts[:help] do
      show_help()
    else
      if opts[:full] && opts[:computed_only] do
        Mix.shell().error("Cannot combine --full and --computed-only")
        Exit.halt(:invalid_args)
      end

      case args do
        [repo_id] ->
          sync_repo(repo_id, opts)

        [] ->
          sync_portfolio(opts)
      end
    end
  end

  defp sync_portfolio(opts) do
    portfolio_path = opts[:portfolio_dir] || default_portfolio_path()

    case PortfolioManager.init(portfolio_path) do
      {:ok, portfolio} ->
        handle_sync_portfolio(portfolio, opts)

      {:error, :not_initialized} ->
        output_not_initialized_error(portfolio_path)
    end
  end

  defp handle_sync_portfolio(portfolio, opts) do
    refresh_opts = build_refresh_opts(opts)
    repos = PortfolioManager.list_repos(portfolio)

    {refreshed, errors} = refresh_all_repos(portfolio, repos, refresh_opts)

    results =
      %{saved: false, refreshed: refreshed, errors: Enum.reverse(errors), views: false}
      |> save_portfolio_state(portfolio)
      |> maybe_regenerate_views(portfolio, opts)

    output_portfolio_results(results, opts)
    maybe_exit_on_errors(results.errors)
  end

  defp refresh_all_repos(portfolio, repos, refresh_opts) do
    Enum.reduce(repos, {0, []}, fn repo, {count, acc} ->
      case refresh_repo_info(portfolio, repo, refresh_opts) do
        :ok -> {count + 1, acc}
        {:error, reason} -> {count, [{repo.id, reason} | acc]}
      end
    end)
  end

  defp save_portfolio_state(results, portfolio) do
    case PortfolioManager.sync(portfolio) do
      :ok -> %{results | saved: true}
      {:error, reason} -> %{results | errors: results.errors ++ [{"portfolio", reason}]}
    end
  end

  defp maybe_regenerate_views(results, portfolio, opts) do
    if opts[:views] do
      do_regenerate_views(results, portfolio)
    else
      results
    end
  end

  defp do_regenerate_views(results, portfolio) do
    case PortfolioManager.generate_views(portfolio) do
      :ok -> %{results | views: true}
      {:error, reason} -> %{results | errors: results.errors ++ [{"views", reason}]}
    end
  end

  defp output_portfolio_results(results, opts) do
    if opts[:json], do: output_json(results), else: output_success(results, opts)
  end

  defp output_not_initialized_error(portfolio_path) do
    Mix.shell().error("""
    Portfolio not found at #{portfolio_path}
    Run `mix portfolio.init` first.
    """)

    Exit.halt(:config)
  end

  defp sync_repo(repo_id, opts) do
    portfolio_path = opts[:portfolio_dir] || default_portfolio_path()

    case PortfolioManager.init(portfolio_path) do
      {:ok, portfolio} ->
        handle_sync_repo(portfolio, repo_id, opts)

      {:error, :not_initialized} ->
        output_not_initialized_error(portfolio_path)
    end
  end

  defp handle_sync_repo(portfolio, repo_id, opts) do
    case PortfolioManager.get_repo(portfolio, repo_id) do
      {:ok, repo} ->
        do_sync_repo(portfolio, repo, repo_id, opts)

      {:error, :not_found} ->
        Mix.shell().error("Repository '#{repo_id}' not found in portfolio")
        Exit.halt(:not_found)
    end
  end

  defp do_sync_repo(portfolio, repo, repo_id, opts) do
    refresh_opts = build_refresh_opts(opts)

    case refresh_repo_info(portfolio, repo, refresh_opts) do
      :ok ->
        PortfolioManager.sync(portfolio)
        {:ok, context} = PortfolioManager.get_context(portfolio, repo_id)
        output_repo_result(context, opts)

      {:error, reason} ->
        Mix.shell().error("Failed to refresh #{repo_id}: #{inspect(reason)}")
        Exit.halt(exit_code_for_error(reason))
    end
  end

  defp output_repo_result(context, opts) do
    if opts[:json], do: output_repo_json(context), else: output_repo_success(context)
  end

  defp refresh_repo_info(_portfolio, %{path: nil}, _opts), do: {:error, :path_not_found}

  defp refresh_repo_info(_portfolio, %{path: path}, _opts) when not is_binary(path),
    do: {:error, :path_not_found}

  defp refresh_repo_info(portfolio, repo, opts) do
    path = repo.path

    if File.dir?(path) do
      do_refresh_repo_info(portfolio, repo, path, opts)
    else
      {:error, :path_not_found}
    end
  end

  defp do_refresh_repo_info(portfolio, repo, path, opts) do
    computed_only = Keyword.get(opts, :computed_only, false)
    full_scan = Keyword.get(opts, :full, false)
    check_remotes = Keyword.get(opts, :check_remotes, false)

    detection = get_detection(path, computed_only)
    updates = build_metadata_updates(path, repo, detection, computed_only)
    computed = build_computed_data(path, detection, check_remotes)
    updates = maybe_add_computed(updates, computed)
    agentic_result = run_agentic_analysis(path, portfolio, repo, full_scan)

    apply_updates_and_agentic(portfolio, repo.id, updates, agentic_result)
  end

  defp get_detection(_path, true), do: nil

  defp get_detection(path, false) do
    {:ok, detection} = FileDetector.detect(path)
    detection
  end

  defp build_metadata_updates(_path, _repo, _detection, true), do: %{}

  defp build_metadata_updates(path, repo, detection, false) do
    %{}
    |> add_git_info(path)
    |> add_detection_info(detection)
    |> add_staleness_status(path, repo)
  end

  defp add_git_info(updates, path) do
    case LocalGit.get_info(path) do
      {:ok, info} -> Map.put(updates, :remote_url, info.remote_url)
      _ -> updates
    end
  end

  defp add_detection_info(updates, nil), do: updates

  defp add_detection_info(updates, detection) do
    updates
    |> Map.put(:language, detection.language)
    |> Map.put(:type, detection.type)
    |> Map.put(:framework, detection.framework)
  end

  defp add_staleness_status(updates, path, repo) do
    {:ok, days} = LocalGit.days_since_last_commit(path)

    if days >= 90 do
      Map.put(updates, :status, :stale)
    else
      maybe_reactivate_stale_repo(updates, repo)
    end
  end

  defp maybe_reactivate_stale_repo(updates, %{status: :stale}),
    do: Map.put(updates, :status, :active)

  defp maybe_reactivate_stale_repo(updates, _repo), do: updates

  defp build_computed_data(path, detection, check_remotes) do
    %{}
    |> add_commit_count(path)
    |> add_contributors(path)
    |> add_first_commit_date(path)
    |> add_last_commit(path)
    |> add_dependencies(path, detection)
    |> maybe_add_remote_data(path, check_remotes)
  end

  defp add_commit_count(computed, path) do
    case LocalGit.commit_count_30d(path) do
      {:ok, count} -> Map.put(computed, "commit_count_30d", count)
      _ -> computed
    end
  end

  defp add_contributors(computed, path) do
    case LocalGit.contributors(path) do
      {:ok, contributors} ->
        computed
        |> Map.put("contributors", contributors)
        |> Map.put("contributor_count", length(contributors))

      _ ->
        computed
    end
  end

  defp add_first_commit_date(computed, path) do
    case LocalGit.first_commit_date(path) do
      {:ok, %DateTime{} = date} ->
        Map.put(computed, "first_commit_date", DateTime.to_iso8601(date))

      _ ->
        computed
    end
  end

  defp add_last_commit(computed, path) do
    case LocalGit.last_commit_info(path) do
      {:ok, %{sha: sha, date: date, message: message}} ->
        Map.put(computed, "last_commit", %{
          "sha" => sha,
          "date" => date && DateTime.to_iso8601(date),
          "message" => message
        })

      _ ->
        computed
    end
  end

  defp add_dependencies(computed, path, detection) do
    case dependency_buckets(path, detection) do
      nil ->
        computed

      deps ->
        Map.put(computed, "dependencies", %{
          "runtime" => Map.get(deps, :runtime, []),
          "dev" => Map.get(deps, :dev, []),
          "optional" => Map.get(deps, :optional, [])
        })
    end
  end

  defp maybe_add_remote_data(computed, _path, false), do: computed

  defp maybe_add_remote_data(computed, path, true) do
    computed
    |> maybe_fetch_remotes(path)
    |> maybe_add_remote_commit(path)
  end

  defp maybe_add_computed(updates, computed) when map_size(computed) > 0 do
    Map.put(updates, :computed, computed)
  end

  defp maybe_add_computed(updates, _computed), do: updates

  defp run_agentic_analysis(_path, _portfolio, _repo, false), do: {:ok, %{pending: 0}}

  defp run_agentic_analysis(path, portfolio, repo, true) do
    Agentic.analyze_with_review(path, portfolio,
      repo_id: repo.id,
      auto_accept_threshold: 0.9
    )
  end

  defp apply_updates_and_agentic(portfolio, repo_id, updates, agentic_result)
       when map_size(updates) > 0 do
    case PortfolioManager.update_context(portfolio, repo_id, updates) do
      {:ok, _} -> finalize_agentic_result(agentic_result)
      error -> error
    end
  end

  defp apply_updates_and_agentic(_portfolio, _repo_id, _updates, agentic_result) do
    finalize_agentic_result(agentic_result)
  end

  defp finalize_agentic_result({:ok, _}), do: :ok

  defp output_json(results) do
    Mix.shell().info(Jason.encode!(results, pretty: true))
  end

  defp output_success(results, _opts) do
    messages = []

    messages = if results.saved, do: messages ++ ["Portfolio state saved"], else: messages

    messages = messages ++ ["Refreshed #{results.refreshed} repositories"]

    messages =
      if results.views,
        do: messages ++ ["Regenerated computed views"],
        else: messages

    error_lines =
      if results.errors == [] do
        []
      else
        ["Errors: #{length(results.errors)}"]
      end

    Mix.shell().info("""
    #{IO.ANSI.green()}Sync complete#{IO.ANSI.reset()}

    #{Enum.join(messages ++ error_lines, "\n")}
    """)
  end

  defp output_repo_json(context) do
    data = %{
      id: context.repo.id,
      name: context.repo.name,
      type: context.repo.type,
      status: context.repo.status,
      language: context.repo.language,
      computed: context.computed
    }

    Mix.shell().info(Jason.encode!(data, pretty: true))
  end

  defp output_repo_success(context) do
    computed = context.computed || %{}
    last_commit_display = format_last_commit(computed)

    Mix.shell().info("""
    #{IO.ANSI.green()}Refreshed #{context.repo.id}#{IO.ANSI.reset()}

    Current state:
      Type:        #{context.repo.type}
      Status:      #{context.repo.status}
      Language:    #{context.repo.language}
      Commits 30d: #{Map.get(computed, "commit_count_30d", "N/A")}
      Last commit: #{last_commit_display}
    """)
  end

  defp show_help do
    Mix.shell().info("""
    Usage: mix portfolio.sync [id] [options]

    Synchronize portfolio state with storage and refresh repository information.

    Options:
      --full            Full rescan including agentic detection
      --computed-only   Only update computed fields
      --check-remotes   Fetch remotes and update remote stats
      --all             Refresh metadata for all repositories (legacy)
      --views           Regenerate computed views (legacy)
      --json            Output result as JSON
      --help            Show this help message

    Examples:
      mix portfolio.sync
      mix portfolio.sync my-app
      mix portfolio.sync --full
      mix portfolio.sync --computed-only
      mix portfolio.sync --check-remotes
    """)
  end

  defp default_portfolio_path do
    System.get_env("PORTFOLIO_DIR") || Path.join(System.user_home!(), "portfolio")
  end

  defp format_last_commit(computed) do
    case Map.get(computed, "last_commit") do
      %{"date" => date} when is_binary(date) -> date
      %{"sha" => sha} when is_binary(sha) -> sha
      value when is_binary(value) -> value
      _ -> "N/A"
    end
  end

  defp dependency_buckets(_path, %{dependencies: deps}) when is_map(deps), do: deps

  defp dependency_buckets(path, _detection) do
    {:ok, deps} = FileDetector.detect_dependencies(path)
    deps
  end

  defp maybe_fetch_remotes(computed, path) do
    _ = LocalGit.fetch_all(path)
    computed
  end

  defp maybe_add_remote_commit(computed, path) do
    case LocalGit.last_remote_commit_info(path) do
      {:ok, %{sha: sha, date: date, message: message}} ->
        Map.put(computed, "last_remote_commit", %{
          "sha" => sha,
          "date" => date && DateTime.to_iso8601(date),
          "message" => message
        })

      _ ->
        computed
    end
  end

  defp build_refresh_opts(opts) do
    [
      computed_only: opts[:computed_only] || false,
      full: opts[:full] || false,
      check_remotes: opts[:check_remotes] || false
    ]
  end

  defp maybe_exit_on_errors([]), do: :ok

  defp maybe_exit_on_errors(errors) do
    error_code =
      errors
      |> Enum.map(&exit_code_for_error(elem(&1, 1)))
      |> Enum.reduce(:error, &prioritize_exit_code/2)

    Exit.halt(error_code)
  end

  defp prioritize_exit_code(:agent, _), do: :agent
  defp prioritize_exit_code(_, :agent), do: :agent
  defp prioritize_exit_code(:git, _), do: :git
  defp prioritize_exit_code(_, :git), do: :git
  defp prioritize_exit_code(_, _), do: :error

  defp exit_code_for_error(reason) do
    case reason do
      :path_not_found -> :git
      {:git, _} -> :git
      {:agentic_failed, _} -> :agent
      :agent_error -> :agent
      _ -> :error
    end
  end
end
