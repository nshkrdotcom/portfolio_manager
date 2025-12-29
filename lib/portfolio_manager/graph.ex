defmodule PortfolioManager.Graph do
  @moduledoc """
  Graph interface for code analysis and knowledge representation.
  """

  alias PortfolioCore.Registry

  @doc """
  Create a new graph.
  """
  @spec create_graph(String.t(), map()) :: :ok | {:error, term()}
  def create_graph(graph_id, config \\ %{}) do
    adapter = get_adapter()
    adapter.create_graph(graph_id, config)
  end

  @doc """
  Add a node to the graph.
  """
  @spec add_node(String.t(), map()) :: {:ok, map()} | {:error, term()}
  def add_node(graph_id, node) do
    adapter = get_adapter()
    adapter.create_node(graph_id, node)
  end

  @doc """
  Add an edge between two nodes.
  """
  @spec add_edge(String.t(), map()) :: {:ok, map()} | {:error, term()}
  def add_edge(graph_id, edge) do
    adapter = get_adapter()
    adapter.create_edge(graph_id, edge)
  end

  @doc """
  Get neighbors of a node.
  """
  @spec neighbors(String.t(), String.t(), keyword()) :: {:ok, [map()]} | {:error, term()}
  def neighbors(graph_id, node_id, opts \\ []) do
    adapter = get_adapter()
    adapter.get_neighbors(graph_id, node_id, opts)
  end

  @doc """
  Execute a raw query on the graph.
  """
  @spec query(String.t(), String.t(), map()) :: {:ok, map()} | {:error, term()}
  def query(graph_id, cypher, params \\ %{}) do
    adapter = get_adapter()
    adapter.query(graph_id, cypher, params)
  end

  @doc """
  Get graph statistics.
  """
  @spec stats(String.t()) :: {:ok, map()} | {:error, term()}
  def stats(graph_id) do
    adapter = get_adapter()
    adapter.graph_stats(graph_id)
  end

  @doc """
  Build dependency graph from repository analysis.
  """
  @spec build_dependency_graph(String.t(), String.t(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def build_dependency_graph(graph_id, repo_path, opts \\ []) do
    with :ok <- create_graph(graph_id, %{type: :dependency}),
         {:ok, deps} <- analyze_dependencies(repo_path, opts),
         :ok <- populate_graph(graph_id, deps) do
      stats(graph_id)
    end
  end

  # Private

  defp get_adapter do
    case Registry.get(:graph_store) do
      {:ok, %{module: module}} -> module
      {:error, :not_found} -> raise "Graph store adapter not configured"
    end
  end

  defp analyze_dependencies(repo_path, opts) do
    language = Keyword.get(opts, :language, :elixir)

    case language do
      :elixir -> analyze_elixir_deps(repo_path)
      :python -> analyze_python_deps(repo_path)
      _ -> {:error, {:unsupported_language, language}}
    end
  end

  defp analyze_elixir_deps(repo_path) do
    mix_exs = Path.join(repo_path, "mix.exs")

    if File.exists?(mix_exs) do
      {:ok, content} = File.read(mix_exs)

      deps =
        Regex.scan(~r/{:(\w+),/, content)
        |> Enum.map(fn [_, name] -> %{name: name, type: :dependency} end)

      {:ok, deps}
    else
      {:error, :mix_exs_not_found}
    end
  end

  defp analyze_python_deps(repo_path) do
    requirements = Path.join(repo_path, "requirements.txt")

    if File.exists?(requirements) do
      {:ok, content} = File.read(requirements)

      deps =
        content
        |> String.split("\n")
        |> Enum.map(&String.trim/1)
        |> Enum.reject(&(String.starts_with?(&1, "#") or &1 == ""))
        |> Enum.map(fn line ->
          name = line |> String.split(~r/[=<>]/) |> List.first() |> String.trim()
          %{name: name, type: :dependency}
        end)

      {:ok, deps}
    else
      {:error, :requirements_not_found}
    end
  end

  defp populate_graph(graph_id, deps) do
    Enum.each(deps, fn dep ->
      node = %{
        id: dep.name,
        labels: ["Dependency"],
        properties: Map.drop(dep, [:name])
      }

      add_node(graph_id, node)
    end)

    :ok
  end
end
