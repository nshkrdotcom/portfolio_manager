defmodule Mix.Tasks.Portfolio.Sync do
  # Suppress dialyzer warnings about Mix functions and defensive error handling
  @dialyzer {:nowarn_function,
             [
               output_json: 1,
               output_success: 2,
               output_repo_json: 1,
               output_repo_success: 1,
               show_help: 0,
               refresh_repo_info: 3
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

  alias PortfolioManager.Adapters.{LocalGit, FileDetector}
  alias PortfolioManager.CLI.Exit

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
    refresh_opts = build_refresh_opts(opts)

    case PortfolioManager.init(portfolio_path) do
      {:ok, portfolio} ->
        repos = PortfolioManager.list_repos(portfolio)

        {refreshed, errors} =
          Enum.reduce(repos, {0, []}, fn repo, {count, acc} ->
            case refresh_repo_info(portfolio, repo, refresh_opts) do
              :ok -> {count + 1, acc}
              {:error, reason} -> {count, [{repo.id, reason} | acc]}
            end
          end)

        results = %{
          saved: false,
          refreshed: refreshed,
          errors: Enum.reverse(errors),
          views: false
        }

        # Save current state
        results =
          case PortfolioManager.sync(portfolio) do
            :ok ->
              %{results | saved: true}

            {:error, reason} ->
              %{results | errors: results.errors ++ [{"portfolio", reason}]}
          end

        # Optionally regenerate views
        results =
          if opts[:views] do
            case PortfolioManager.generate_views(portfolio) do
              :ok ->
                %{results | views: true}

              {:error, reason} ->
                %{results | errors: results.errors ++ [{"views", reason}]}
            end
          else
            results
          end

        if opts[:json] do
          output_json(results)
        else
          output_success(results, opts)
        end

        maybe_exit_on_errors(results.errors)

      {:error, :not_initialized} ->
        Mix.shell().error("""
        Portfolio not found at #{portfolio_path}
        Run `mix portfolio.init` first.
        """)

        Exit.halt(:config)
    end
  end

  defp sync_repo(repo_id, opts) do
    portfolio_path = opts[:portfolio_dir] || default_portfolio_path()

    case PortfolioManager.init(portfolio_path) do
      {:ok, portfolio} ->
        case PortfolioManager.get_repo(portfolio, repo_id) do
          {:ok, repo} ->
            refresh_opts = build_refresh_opts(opts)

            case refresh_repo_info(portfolio, repo, refresh_opts) do
              :ok ->
                PortfolioManager.sync(portfolio)
                {:ok, context} = PortfolioManager.get_context(portfolio, repo_id)

                if opts[:json] do
                  output_repo_json(context)
                else
                  output_repo_success(context)
                end

              {:error, reason} ->
                Mix.shell().error("Failed to refresh #{repo_id}: #{inspect(reason)}")
                Exit.halt(exit_code_for_error(reason))
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

  defp refresh_repo_info(portfolio, repo, opts) do
    path = repo.path

    if path && File.dir?(path) do
      computed_only = Keyword.get(opts, :computed_only, false)
      full_scan = Keyword.get(opts, :full, false)
      check_remotes = Keyword.get(opts, :check_remotes, false)

      updates = %{}

      detection =
        if computed_only do
          nil
        else
          case FileDetector.detect(path) do
            {:ok, detection} -> detection
            _ -> nil
          end
        end

      updates =
        if computed_only do
          updates
        else
          updates =
            case LocalGit.get_info(path) do
              {:ok, info} ->
                Map.merge(updates, %{
                  remote_url: info.remote_url
                })

              _ ->
                updates
            end

          updates =
            if detection do
              updates
              |> Map.put(:language, detection.language)
              |> Map.put(:type, detection.type)
              |> Map.put(:framework, detection.framework)
            else
              updates
            end

          case LocalGit.days_since_last_commit(path) do
            {:ok, days} when days >= 90 ->
              Map.put(updates, :status, :stale)

            {:ok, _} ->
              if repo.status == :stale, do: Map.put(updates, :status, :active), else: updates

            _ ->
              updates
          end
        end

      # Update computed data
      computed = %{}

      computed =
        case LocalGit.commit_count_30d(path) do
          {:ok, count} -> Map.put(computed, "commit_count_30d", count)
          _ -> computed
        end

      computed =
        case LocalGit.contributors(path) do
          {:ok, contributors} ->
            computed
            |> Map.put("contributors", contributors)
            |> Map.put("contributor_count", length(contributors))

          _ ->
            computed
        end

      computed =
        case LocalGit.first_commit_date(path) do
          {:ok, %DateTime{} = date} ->
            Map.put(computed, "first_commit_date", DateTime.to_iso8601(date))

          _ ->
            computed
        end

      computed =
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

      computed =
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

      computed =
        if check_remotes do
          computed
          |> maybe_fetch_remotes(path)
          |> maybe_add_remote_commit(path)
        else
          computed
        end

      updates =
        if map_size(computed) > 0, do: Map.put(updates, :computed, computed), else: updates

      agentic_result =
        if full_scan do
          PortfolioManager.Detection.Agentic.analyze_with_review(path, portfolio,
            repo_id: repo.id,
            auto_accept_threshold: 0.9
          )
        else
          {:ok, %{pending: 0}}
        end

      if map_size(updates) > 0 do
        case PortfolioManager.update_context(portfolio, repo.id, updates) do
          {:ok, _} ->
            case agentic_result do
              {:ok, _} -> :ok
              {:error, reason} -> {:error, {:agentic_failed, reason}}
            end

          error ->
            error
        end
      else
        case agentic_result do
          {:ok, _} -> :ok
          {:error, reason} -> {:error, {:agentic_failed, reason}}
        end
      end
    else
      {:error, :path_not_found}
    end
  end

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
