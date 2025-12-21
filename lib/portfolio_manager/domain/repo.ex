defmodule PortfolioManager.Domain.Repo do
  @moduledoc """
  Domain entity representing a tracked repository.

  A Repo contains all the metadata about a software repository
  being tracked in the portfolio.
  """

  @type repo_type ::
          :library
          | :application
          | :port
          | :fork
          | :experiment
          | :template
          | :config
          | :docs
          | :unknown

  @type status :: :active | :maintenance | :stale | :blocked | :archived | :unknown

  @type t :: %__MODULE__{
          id: String.t(),
          name: String.t(),
          path: String.t() | nil,
          remote_url: String.t() | nil,
          type: repo_type(),
          status: status(),
          language: atom() | nil,
          purpose: String.t() | nil,
          tags: [String.t()],
          priority: :high | :medium | :low | nil,
          port: port_info() | nil,
          created_at: DateTime.t(),
          updated_at: DateTime.t()
        }

  @type port_info :: %{
          upstream_url: String.t(),
          upstream_language: String.t() | nil,
          coverage: String.t() | nil,
          last_synced_commit: String.t() | nil
        }

  defstruct [
    :id,
    :name,
    :path,
    :remote_url,
    :type,
    :status,
    :language,
    :purpose,
    :priority,
    :port,
    tags: [],
    created_at: nil,
    updated_at: nil
  ]

  @valid_types [
    :library,
    :application,
    :port,
    :fork,
    :experiment,
    :template,
    :config,
    :docs,
    :unknown
  ]
  @valid_statuses [:active, :maintenance, :stale, :blocked, :archived, :unknown]
  @valid_priorities [:high, :medium, :low]

  @doc """
  Creates a new Repo struct with the given attributes.

  ## Examples

      iex> {:ok, repo} = PortfolioManager.Domain.Repo.new(%{id: "my-repo", name: "My Repo"})
      iex> repo.id
      "my-repo"

  """
  @spec new(map()) :: {:ok, t()} | {:error, term()}
  def new(attrs) when is_map(attrs) do
    now = DateTime.utc_now()

    repo = %__MODULE__{
      id: Map.get(attrs, :id) || Map.get(attrs, "id"),
      name: Map.get(attrs, :name) || Map.get(attrs, "name"),
      path: Map.get(attrs, :path) || Map.get(attrs, "path"),
      remote_url: Map.get(attrs, :remote_url) || Map.get(attrs, "remote_url"),
      type: normalize_type(Map.get(attrs, :type) || Map.get(attrs, "type")),
      status: normalize_status(Map.get(attrs, :status) || Map.get(attrs, "status")),
      language: normalize_atom(Map.get(attrs, :language) || Map.get(attrs, "language")),
      purpose: Map.get(attrs, :purpose) || Map.get(attrs, "purpose"),
      tags: Map.get(attrs, :tags) || Map.get(attrs, "tags") || [],
      priority: normalize_priority(Map.get(attrs, :priority) || Map.get(attrs, "priority")),
      port: normalize_port(Map.get(attrs, :port) || Map.get(attrs, "port")),
      created_at: Map.get(attrs, :created_at) || now,
      updated_at: Map.get(attrs, :updated_at) || now
    }

    validate(repo)
  end

  @doc """
  Creates a new Repo struct, raising on error.
  """
  @spec new!(map()) :: t()
  def new!(attrs) do
    case new(attrs) do
      {:ok, repo} -> repo
      {:error, reason} -> raise ArgumentError, "Invalid repo: #{inspect(reason)}"
    end
  end

  @doc """
  Updates a repo with the given attributes.
  """
  @spec update(t(), map()) :: {:ok, t()} | {:error, term()}
  def update(%__MODULE__{} = repo, attrs) when is_map(attrs) do
    updated =
      repo
      |> maybe_update(:name, attrs)
      |> maybe_update(:path, attrs)
      |> maybe_update(:remote_url, attrs)
      |> maybe_update(:type, attrs, &normalize_type/1)
      |> maybe_update(:status, attrs, &normalize_status/1)
      |> maybe_update(:language, attrs, &normalize_atom/1)
      |> maybe_update(:purpose, attrs)
      |> maybe_update(:tags, attrs)
      |> maybe_update(:priority, attrs, &normalize_priority/1)
      |> maybe_update(:port, attrs, &normalize_port/1)
      |> Map.put(:updated_at, DateTime.utc_now())

    validate(updated)
  end

  @doc """
  Validates a repo struct.
  """
  @spec validate(t()) :: {:ok, t()} | {:error, term()}
  def validate(%__MODULE__{} = repo) do
    cond do
      is_nil(repo.id) or repo.id == "" ->
        {:error, :id_required}

      repo.type not in @valid_types ->
        {:error, {:invalid_type, repo.type}}

      repo.status not in @valid_statuses ->
        {:error, {:invalid_status, repo.status}}

      not is_nil(repo.priority) and repo.priority not in @valid_priorities ->
        {:error, {:invalid_priority, repo.priority}}

      true ->
        {:ok, repo}
    end
  end

  @doc """
  Converts a repo to a map suitable for YAML serialization.
  """
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = repo) do
    %{
      "id" => repo.id,
      "name" => repo.name,
      "path" => repo.path,
      "remote_url" => repo.remote_url,
      "type" => to_string(repo.type),
      "status" => to_string(repo.status),
      "language" => repo.language && to_string(repo.language),
      "purpose" => repo.purpose,
      "tags" => repo.tags,
      "priority" => repo.priority && to_string(repo.priority),
      "port" => repo.port,
      "created_at" => repo.created_at && DateTime.to_iso8601(repo.created_at),
      "updated_at" => repo.updated_at && DateTime.to_iso8601(repo.updated_at)
    }
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Map.new()
  end

  @doc """
  Generates an ID from a path or name.
  """
  @spec generate_id(String.t()) :: String.t()
  def generate_id(path_or_name) do
    path_or_name
    |> Path.basename()
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9_-]/, "-")
    |> String.replace(~r/-+/, "-")
    |> String.trim("-")
  end

  # Private helpers

  defp normalize_type(nil), do: :unknown
  defp normalize_type(type) when is_atom(type) and type in @valid_types, do: type

  defp normalize_type(type) when is_binary(type),
    do: normalize_type(String.to_existing_atom(type))

  defp normalize_type(_), do: :unknown

  defp normalize_status(nil), do: :unknown
  defp normalize_status(status) when is_atom(status) and status in @valid_statuses, do: status

  defp normalize_status(status) when is_binary(status),
    do: normalize_status(String.to_existing_atom(status))

  defp normalize_status(_), do: :unknown

  defp normalize_priority(nil), do: nil
  defp normalize_priority(p) when is_atom(p) and p in @valid_priorities, do: p
  defp normalize_priority(p) when is_binary(p), do: normalize_priority(String.to_existing_atom(p))
  defp normalize_priority(_), do: nil

  defp normalize_atom(nil), do: nil
  defp normalize_atom(a) when is_atom(a), do: a
  defp normalize_atom(s) when is_binary(s), do: String.to_atom(s)

  defp normalize_port(nil), do: nil
  defp normalize_port(port) when is_map(port), do: port

  defp maybe_update(repo, key, attrs, normalizer \\ nil) do
    str_key = to_string(key)

    value =
      cond do
        Map.has_key?(attrs, key) -> Map.get(attrs, key)
        Map.has_key?(attrs, str_key) -> Map.get(attrs, str_key)
        true -> nil
      end

    if value do
      normalized = if normalizer, do: normalizer.(value), else: value
      Map.put(repo, key, normalized)
    else
      repo
    end
  end
end
