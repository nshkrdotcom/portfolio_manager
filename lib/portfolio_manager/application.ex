defmodule PortfolioManager.Application do
  @moduledoc false

  use Application
  require Logger

  alias PortfolioCore.Manifest.Loader

  @impl true
  def start(_type, _args) do
    manifest =
      case Application.get_env(:portfolio_manager, :manifest, :auto) do
        :auto -> load_manifest_for_pipelines()
        %{} = configured -> configured
        other -> other
      end

    Application.put_env(:portfolio_manager, :manifest, manifest)

    children =
      [
        repo_child(),
        registry_child(),
        # Note: PortfolioCore.Manifest.Engine is started by portfolio_core's supervision tree.
        # Configure it via :portfolio_core, :manifest in config.exs
        PortfolioManager.Domain.Registry,
        router_child(),
        pipeline_children()
      ]
      |> List.flatten()
      |> Enum.reject(&is_nil/1)

    opts = [strategy: :one_for_one, name: PortfolioManager.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp registry_child do
    %{
      id: PortfolioCore.Registry,
      start: {__MODULE__, :start_registry, []}
    }
  end

  def start_registry do
    case Process.whereis(PortfolioCore.Registry) do
      nil -> PortfolioCore.Registry.start_link([])
      _pid -> :ignore
    end
  end

  defp repo_child do
    if Application.get_env(:portfolio_manager, :start_repo, true) do
      PortfolioManager.Repo
    end
  end

  defp router_child do
    if Application.get_env(:portfolio_manager, :start_router, true) do
      manifest = Application.get_env(:portfolio_manager, :manifest, %{})
      router_config = get_in(manifest, [:router]) || %{}

      strategy = to_strategy(router_config[:strategy])
      health_interval = router_config[:health_check_interval] || 30_000
      providers = build_router_providers(router_config[:providers] || [])

      {PortfolioManager.Router,
       strategy: strategy, providers: providers, health_check_interval: health_interval}
    end
  end

  defp to_strategy(nil), do: :fallback
  defp to_strategy(s) when is_atom(s), do: s
  defp to_strategy(s) when is_binary(s), do: String.to_atom(s)

  defp build_router_providers(provider_configs) do
    Enum.map(provider_configs, fn config ->
      %{
        name: to_atom(config[:name]),
        module: resolve_module(config[:module]),
        config: config[:config] || %{},
        capabilities: Enum.map(config[:capabilities] || [], &to_atom/1),
        priority: config[:priority] || 1,
        cost_per_token: config[:cost_per_token]
      }
    end)
  end

  defp resolve_module(nil), do: nil

  defp resolve_module(module) when is_atom(module), do: module

  defp resolve_module(module) when is_binary(module) do
    String.to_existing_atom("Elixir.#{module}")
  rescue
    ArgumentError -> String.to_atom("Elixir.#{module}")
  end

  defp to_atom(value) when is_atom(value), do: value
  defp to_atom(value) when is_binary(value), do: String.to_atom(value)

  defp manifest_path do
    env = Application.get_env(:portfolio_manager, :env, :development)

    env_name =
      case env do
        :dev -> "development"
        :prod -> "production"
        other -> to_string(other)
      end

    manifest_rel = Path.join("config/manifests", "#{env_name}.yml")

    configured =
      Application.get_env(:portfolio_manager, :manifest_path) ||
        Application.get_env(:portfolio_core, :manifest, []) |> Keyword.get(:manifest_path)

    candidates =
      [configured, manifest_rel, Application.app_dir(:portfolio_manager, manifest_rel)]
      |> Enum.filter(&is_binary/1)
      |> Enum.map(&expand_manifest_path/1)

    Enum.find(candidates, &File.exists?/1) || expand_manifest_path(manifest_rel)
  end

  defp load_manifest_for_pipelines do
    path = manifest_path()

    case Loader.load(path) do
      {:ok, manifest} ->
        atomize_keys(manifest)

      {:error, reason} ->
        Logger.warning("Failed to load manifest for pipelines: #{inspect(reason)}")
        %{}
    end
  end

  defp pipeline_children do
    manifest = Application.get_env(:portfolio_manager, :manifest, %{})

    children = []

    children =
      if get_in(manifest, [:pipelines, :ingestion, :enabled]) do
        [{PortfolioIndex.Pipelines.Ingestion, ingestion_opts(manifest)} | children]
      else
        children
      end

    children =
      if get_in(manifest, [:pipelines, :embedding, :enabled]) do
        [{PortfolioIndex.Pipelines.Embedding, embedding_opts(manifest)} | children]
      else
        children
      end

    children
  end

  defp ingestion_opts(manifest) do
    config = get_in(manifest, [:pipelines, :ingestion]) || %{}

    [
      concurrency: config[:concurrency] || 10,
      batch_size: config[:batch_size] || 50
    ]
  end

  defp embedding_opts(manifest) do
    config = get_in(manifest, [:pipelines, :embedding]) || %{}

    [
      concurrency: config[:concurrency] || 5,
      rate_limit: config[:rate_limit] || 100
    ]
  end

  defp atomize_keys(map) when is_map(map) do
    Map.new(map, fn {k, v} -> {to_atom_key(k), atomize_keys(v)} end)
  end

  defp atomize_keys(list) when is_list(list) do
    Enum.map(list, &atomize_keys/1)
  end

  defp atomize_keys(value), do: value

  defp to_atom_key(key) when is_atom(key), do: key
  defp to_atom_key(key) when is_binary(key), do: String.to_atom(key)

  defp expand_manifest_path(path) do
    if Path.type(path) == :absolute do
      path
    else
      Path.expand(path)
    end
  end
end
