defmodule PortfolioManager.Application do
  @moduledoc false

  use Application
  require Logger

  alias PortfolioCore.Manifest.Loader

  @impl true
  def start(_type, _args) do
    Application.put_env(:portfolio_manager, :manifest, load_manifest_for_pipelines())

    children =
      [
        repo_child(),
        registry_child(),
        # Note: PortfolioCore.Manifest.Engine is started by portfolio_core's supervision tree.
        # Configure it via :portfolio_core, :manifest in config.exs
        PortfolioManager.Domain.Registry,
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

  defp manifest_path do
    env = Application.get_env(:portfolio_manager, :env, :development)

    env_name =
      case env do
        :dev -> "development"
        :prod -> "production"
        other -> to_string(other)
      end

    Path.join(["config", "manifests", "#{env_name}.yml"])
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
end
