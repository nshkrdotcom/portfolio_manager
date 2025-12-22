defmodule PortfolioManager.Domain.Registry do
  @moduledoc """
  Domain service for managing the repository registry.

  The registry is the central catalog of all tracked repositories.
  """

  alias PortfolioManager.Domain.{Repo, Relationship}

  @type t :: %__MODULE__{
          repos: %{String.t() => Repo.t()},
          relationships: [Relationship.t()]
        }

  defstruct repos: %{}, relationships: []

  @doc """
  Creates a new empty registry.
  """
  @spec new() :: t()
  def new do
    %__MODULE__{}
  end

  @doc """
  Loads a registry from repo and relationship data.
  """
  @spec from_data(list(), list()) :: {:ok, t()} | {:error, term()}
  def from_data(repos_data, relationships_data)
      when is_list(repos_data) and is_list(relationships_data) do
    repos_result =
      Enum.reduce_while(repos_data, {:ok, %{}}, fn repo_data, {:ok, acc} ->
        case Repo.new(repo_data) do
          {:ok, repo} -> {:cont, {:ok, Map.put(acc, repo.id, repo)}}
          {:error, _} = error -> {:halt, error}
        end
      end)

    rels_result =
      Enum.reduce_while(relationships_data, {:ok, []}, fn rel_data, {:ok, acc} ->
        case Relationship.new(rel_data) do
          {:ok, rel} -> {:cont, {:ok, [rel | acc]}}
          {:error, _} = error -> {:halt, error}
        end
      end)

    with {:ok, repos} <- repos_result,
         {:ok, rels} <- rels_result do
      {:ok, %__MODULE__{repos: repos, relationships: Enum.reverse(rels)}}
    end
  end

  @doc """
  Adds a repo to the registry.
  """
  @spec add_repo(t(), Repo.t()) :: {:ok, t()} | {:error, :already_exists}
  def add_repo(%__MODULE__{} = registry, %Repo{} = repo) do
    if Map.has_key?(registry.repos, repo.id) do
      {:error, :already_exists}
    else
      {:ok, %{registry | repos: Map.put(registry.repos, repo.id, repo)}}
    end
  end

  @doc """
  Updates a repo in the registry.
  """
  @spec update_repo(t(), String.t(), map()) :: {:ok, t()} | {:error, term()}
  def update_repo(%__MODULE__{} = registry, repo_id, updates) do
    case Map.fetch(registry.repos, repo_id) do
      {:ok, repo} ->
        with {:ok, updated} <- Repo.update(repo, updates) do
          {:ok, %{registry | repos: Map.put(registry.repos, repo_id, updated)}}
        end

      :error ->
        {:error, :not_found}
    end
  end

  @doc """
  Removes a repo from the registry.
  """
  @spec remove_repo(t(), String.t()) :: {:ok, t()} | {:error, :not_found}
  def remove_repo(%__MODULE__{} = registry, repo_id) do
    if Map.has_key?(registry.repos, repo_id) do
      updated_repos = Map.delete(registry.repos, repo_id)

      updated_rels =
        Enum.reject(registry.relationships, fn rel ->
          rel.from == repo_id or rel.to == repo_id
        end)

      {:ok, %{registry | repos: updated_repos, relationships: updated_rels}}
    else
      {:error, :not_found}
    end
  end

  @doc """
  Gets a repo by ID.
  """
  @spec get_repo(t(), String.t()) :: {:ok, Repo.t()} | {:error, :not_found}
  def get_repo(%__MODULE__{} = registry, repo_id) do
    case Map.fetch(registry.repos, repo_id) do
      {:ok, repo} -> {:ok, repo}
      :error -> {:error, :not_found}
    end
  end

  @doc """
  Lists all repos, optionally filtered.
  """
  @spec list_repos(t(), keyword()) :: [Repo.t()]
  def list_repos(%__MODULE__{} = registry, opts \\ []) do
    registry.repos
    |> Map.values()
    |> filter_repos(opts)
    |> sort_repos(Keyword.get(opts, :sort, :name))
  end

  @doc """
  Adds a relationship.
  """
  @spec add_relationship(t(), Relationship.t()) :: {:ok, t()}
  def add_relationship(%__MODULE__{} = registry, %Relationship{} = rel) do
    # Remove existing relationship with same from/to/type if exists
    updated_rels =
      Enum.reject(registry.relationships, fn r ->
        r.from == rel.from and r.to == rel.to and r.type == rel.type
      end)

    {:ok, %{registry | relationships: updated_rels ++ [rel]}}
  end

  @doc """
  Gets relationships for a repo.
  """
  @spec get_relationships(t(), String.t()) :: [Relationship.t()]
  def get_relationships(%__MODULE__{} = registry, repo_id) do
    Enum.filter(registry.relationships, fn rel ->
      rel.from == repo_id or rel.to == repo_id
    end)
  end

  @doc """
  Searches repos by query string.
  """
  @spec search(t(), String.t(), keyword()) :: [Repo.t()]
  def search(%__MODULE__{} = registry, query, opts \\ []) do
    fields = Keyword.get(opts, :fields, [:id, :name, :purpose, :tags])
    regex? = Keyword.get(opts, :regex, false)
    case_sensitive? = Keyword.get(opts, :case_sensitive, false)

    regex =
      if regex? do
        flags = if case_sensitive?, do: "", else: "i"

        case Regex.compile(query, flags) do
          {:ok, compiled} -> compiled
          {:error, _} -> :invalid
        end
      else
        nil
      end

    registry.repos
    |> Map.values()
    |> Enum.filter(fn repo ->
      Enum.any?(fields, fn field ->
        value = Map.get(repo, field)
        matches_query?(value, query, regex, case_sensitive?)
      end)
    end)
  end

  @doc """
  Returns registry statistics.
  """
  @spec stats(t()) :: map()
  def stats(%__MODULE__{} = registry) do
    repos = Map.values(registry.repos)

    %{
      total: length(repos),
      by_status: group_count(repos, :status),
      by_type: group_count(repos, :type),
      by_language: group_count(repos, :language),
      relationships: length(registry.relationships)
    }
  end

  @doc """
  Converts registry to serializable data.
  """
  @spec to_data(t()) :: {list(), list()}
  def to_data(%__MODULE__{} = registry) do
    repos_data =
      registry.repos
      |> Map.values()
      |> Enum.map(&Repo.to_map/1)

    rels_data =
      registry.relationships
      |> Enum.map(&Relationship.to_map/1)

    {repos_data, rels_data}
  end

  # Private helpers

  defp filter_repos(repos, opts) do
    repos
    |> maybe_filter(:status, Keyword.get(opts, :status))
    |> maybe_filter(:type, Keyword.get(opts, :type))
    |> maybe_filter(:language, Keyword.get(opts, :language))
    |> maybe_filter_tags(Keyword.get(opts, :tags))
  end

  defp maybe_filter(repos, _field, nil), do: repos

  defp maybe_filter(repos, field, value) do
    Enum.filter(repos, fn repo ->
      Map.get(repo, field) == value
    end)
  end

  defp maybe_filter_tags(repos, nil), do: repos

  defp maybe_filter_tags(repos, tags) when is_list(tags) do
    Enum.filter(repos, fn repo ->
      Enum.any?(tags, fn tag -> tag in repo.tags end)
    end)
  end

  defp sort_repos(repos, :name), do: Enum.sort_by(repos, & &1.name)
  defp sort_repos(repos, :id), do: Enum.sort_by(repos, & &1.id)
  defp sort_repos(repos, :updated_at), do: Enum.sort_by(repos, & &1.updated_at, {:desc, DateTime})
  defp sort_repos(repos, _), do: repos

  defp matches_query?(_value, _query, :invalid, _case_sensitive?), do: false
  defp matches_query?(nil, _query, _regex, _case_sensitive?), do: false

  defp matches_query?(value, _query, %Regex{} = regex, _case_sensitive?) when is_binary(value),
    do: Regex.match?(regex, value)

  defp matches_query?(value, query, nil, case_sensitive?) when is_binary(value) do
    if case_sensitive? do
      String.contains?(value, query)
    else
      String.contains?(String.downcase(value), String.downcase(query))
    end
  end

  defp matches_query?(values, query, regex, case_sensitive?) when is_list(values),
    do: Enum.any?(values, &matches_query?(&1, query, regex, case_sensitive?))

  defp matches_query?(value, query, regex, case_sensitive?) when is_atom(value),
    do: matches_query?(to_string(value), query, regex, case_sensitive?)

  defp matches_query?(_, _query, _regex, _case_sensitive?), do: false

  defp group_count(repos, field) do
    repos
    |> Enum.group_by(&Map.get(&1, field))
    |> Enum.map(fn {k, v} -> {k, length(v)} end)
    |> Map.new()
  end
end
