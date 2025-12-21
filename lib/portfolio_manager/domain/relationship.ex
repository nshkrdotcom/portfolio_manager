defmodule PortfolioManager.Domain.Relationship do
  @moduledoc """
  Domain entity representing a relationship between two repositories.
  """

  @type relationship_type :: :depends_on | :port_of | :fork_of | :evolved_from | :related_to

  @type t :: %__MODULE__{
          id: String.t(),
          from: String.t(),
          to: String.t(),
          type: relationship_type(),
          details: map(),
          created_at: DateTime.t()
        }

  defstruct [:id, :from, :to, :type, details: %{}, created_at: nil]

  @valid_types [:depends_on, :port_of, :fork_of, :evolved_from, :related_to]

  @doc """
  Creates a new Relationship struct.

  ## Examples

      iex> {:ok, rel} = PortfolioManager.Domain.Relationship.new(%{
      ...>   from: "my-port",
      ...>   to: "upstream-lib",
      ...>   type: :port_of
      ...> })
      iex> rel.type
      :port_of

  """
  @spec new(map()) :: {:ok, t()} | {:error, term()}
  def new(attrs) when is_map(attrs) do
    rel_type = normalize_type(Map.get(attrs, :type) || Map.get(attrs, "type"))
    from = Map.get(attrs, :from) || Map.get(attrs, "from")
    to = Map.get(attrs, :to) || Map.get(attrs, "to")

    rel = %__MODULE__{
      id: Map.get(attrs, :id) || Map.get(attrs, "id") || generate_id(from, to, rel_type),
      from: from,
      to: to,
      type: rel_type,
      details: Map.get(attrs, :details) || Map.get(attrs, "details") || %{},
      created_at: Map.get(attrs, :created_at) || DateTime.utc_now()
    }

    validate(rel)
  end

  @doc """
  Creates a new Relationship struct, raising on error.
  """
  @spec new!(map()) :: t()
  def new!(attrs) do
    case new(attrs) do
      {:ok, rel} -> rel
      {:error, reason} -> raise ArgumentError, "Invalid relationship: #{inspect(reason)}"
    end
  end

  @doc """
  Validates a relationship struct.
  """
  @spec validate(t()) :: {:ok, t()} | {:error, term()}
  def validate(%__MODULE__{} = rel) do
    cond do
      is_nil(rel.from) or rel.from == "" ->
        {:error, :from_required}

      is_nil(rel.to) or rel.to == "" ->
        {:error, :to_required}

      rel.type not in @valid_types ->
        {:error, {:invalid_type, rel.type}}

      true ->
        {:ok, rel}
    end
  end

  @doc """
  Converts a relationship to a map for serialization.
  """
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = rel) do
    %{
      "id" => rel.id,
      "from" => rel.from,
      "to" => rel.to,
      "type" => to_string(rel.type),
      "details" => rel.details,
      "created_at" => rel.created_at && DateTime.to_iso8601(rel.created_at)
    }
    |> Enum.reject(fn {_k, v} -> is_nil(v) or v == %{} end)
    |> Map.new()
  end

  @doc """
  Returns valid relationship types.
  """
  @spec valid_types() :: [relationship_type()]
  def valid_types, do: @valid_types

  # Private helpers

  defp normalize_type(nil), do: :related_to
  defp normalize_type(type) when is_atom(type) and type in @valid_types, do: type

  defp normalize_type(type) when is_binary(type),
    do: normalize_type(String.to_existing_atom(type))

  defp normalize_type(_), do: :related_to

  defp generate_id(from, to, type) do
    "#{from}--#{type}--#{to}"
  end
end
