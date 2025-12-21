defmodule Mix.Tasks.Portfolio.Sync do
  # Suppress dialyzer warnings about Mix functions and defensive error handling
  @dialyzer {:nowarn_function,
             [
               output_json: 1,
               output_success: 2,
               output_repo_json: 1,
               output_repo_success: 1,
               show_help: 0,
               refresh_repo_info: 2
             ]}

  @moduledoc """
  Synchronize portfolio state with storage and refresh repository information.

  ## Usage

      mix portfolio.sync [id]

  ## Options

    * `--all` - Refresh metadata for all repositories
    * `--views` - Regenerate computed views
    * `--json` - Output result as JSON
    * `--help` - Show help message

  ## Examples

      # Sync portfolio state to storage
      mix portfolio.sync

      # Refresh a specific repository
      mix portfolio.sync my-app

      # Refresh all repositories and regenerate views
      mix portfolio.sync --all --views

  """
  @shortdoc "Synchronize portfolio state"

  use Mix.Task

  alias PortfolioManager.Adapters.{LocalGit, FileDetector}

  @impl Mix.Task
  def run(args) do
    {opts, args, _} =
      OptionParser.parse(args,
        strict: [
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
        results = %{saved: false, refreshed: 0, views: false}

        # Save current state
        results =
          case PortfolioManager.sync(portfolio) do
            :ok -> %{results | saved: true}
            {:error, _} -> results
          end

        # Optionally refresh all repos
        results =
          if opts[:all] do
            repos = PortfolioManager.list_repos(portfolio)

            refreshed =
              Enum.count(repos, fn repo ->
                case refresh_repo_info(portfolio, repo) do
                  :ok -> true
                  _ -> false
                end
              end)

            PortfolioManager.sync(portfolio)
            %{results | refreshed: refreshed}
          else
            results
          end

        # Optionally regenerate views
        results =
          if opts[:views] do
            case PortfolioManager.generate_views(portfolio) do
              :ok -> %{results | views: true}
              {:error, _} -> results
            end
          else
            results
          end

        if opts[:json] do
          output_json(results)
        else
          output_success(results, opts)
        end

      {:error, :not_initialized} ->
        Mix.shell().error("""
        Portfolio not found at #{portfolio_path}
        Run `mix portfolio.init` first.
        """)
    end
  end

  defp sync_repo(repo_id, opts) do
    portfolio_path = opts[:portfolio_dir] || default_portfolio_path()

    case PortfolioManager.init(portfolio_path) do
      {:ok, portfolio} ->
        case PortfolioManager.get_repo(portfolio, repo_id) do
          {:ok, repo} ->
            case refresh_repo_info(portfolio, repo) do
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

  defp refresh_repo_info(portfolio, repo) do
    path = repo.path

    if path && File.dir?(path) do
      updates = %{}

      # Get git info
      updates =
        case LocalGit.get_info(path) do
          {:ok, info} ->
            Map.merge(updates, %{
              remote_url: info.remote_url
            })

          _ ->
            updates
        end

      # Get detection info
      updates =
        case FileDetector.detect(path) do
          {:ok, detection} ->
            updates
            |> Map.put(:language, detection.language)
            |> Map.put(:type, detection.type)

          _ ->
            updates
        end

      # Get commit stats
      updates =
        case LocalGit.days_since_last_commit(path) do
          {:ok, days} when days >= 90 ->
            Map.put(updates, :status, :stale)

          {:ok, _} ->
            if repo.status == :stale, do: Map.put(updates, :status, :active), else: updates

          _ ->
            updates
        end

      # Update computed data
      computed = %{}

      computed =
        case LocalGit.commit_count_30d(path) do
          {:ok, count} -> Map.put(computed, "commits_30d", count)
          _ -> computed
        end

      computed =
        case LocalGit.contributor_count(path) do
          {:ok, count} -> Map.put(computed, "contributors", count)
          _ -> computed
        end

      computed =
        case LocalGit.get_last_commit_date(path) do
          {:ok, date} when not is_nil(date) ->
            Map.put(computed, "last_commit", DateTime.to_iso8601(date))

          _ ->
            computed
        end

      updates =
        if map_size(computed) > 0, do: Map.put(updates, :computed, computed), else: updates

      if map_size(updates) > 0 do
        case PortfolioManager.update_context(portfolio, repo.id, updates) do
          {:ok, _} -> :ok
          error -> error
        end
      else
        :ok
      end
    else
      {:error, :path_not_found}
    end
  end

  defp output_json(results) do
    Mix.shell().info(Jason.encode!(results, pretty: true))
  end

  defp output_success(results, opts) do
    messages = []

    messages = if results.saved, do: messages ++ ["Portfolio state saved"], else: messages

    messages =
      if opts[:all],
        do: messages ++ ["Refreshed #{results.refreshed} repositories"],
        else: messages

    messages =
      if results.views,
        do: messages ++ ["Regenerated computed views"],
        else: messages

    Mix.shell().info("""
    #{IO.ANSI.green()}Sync complete#{IO.ANSI.reset()}

    #{Enum.join(messages, "\n")}
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

    Mix.shell().info("""
    #{IO.ANSI.green()}Refreshed #{context.repo.id}#{IO.ANSI.reset()}

    Current state:
      Type:        #{context.repo.type}
      Status:      #{context.repo.status}
      Language:    #{context.repo.language}
      Commits 30d: #{Map.get(computed, "commits_30d", "N/A")}
      Last commit: #{Map.get(computed, "last_commit", "N/A")}
    """)
  end

  defp show_help do
    Mix.shell().info("""
    Usage: mix portfolio.sync [id] [options]

    Synchronize portfolio state with storage and refresh repository information.

    Options:
      --all          Refresh metadata for all repositories
      --views        Regenerate computed views
      --json         Output result as JSON
      --help         Show this help message

    Examples:
      mix portfolio.sync
      mix portfolio.sync my-app
      mix portfolio.sync --all --views
    """)
  end

  defp default_portfolio_path do
    System.get_env("PORTFOLIO_DIR") || Path.join(System.user_home!(), ".portfolio")
  end
end
