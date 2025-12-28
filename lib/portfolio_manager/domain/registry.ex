defmodule PortfolioManager.Domain.Registry do
  @moduledoc """
  Lightweight in-memory registry for domain entities.

  This keeps domain metadata available during a running session without
  forcing a persistence dependency in the application layer.
  """

  use GenServer

  @type entity_type :: atom()
  @type entity_id :: String.t()
  @type attributes :: map()

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @spec register(entity_type(), entity_id(), attributes()) :: :ok
  def register(type, id, attrs) do
    GenServer.call(__MODULE__, {:register, type, id, attrs})
  end

  @spec get(entity_type(), entity_id()) :: {:ok, attributes()} | {:error, :not_found}
  def get(type, id) do
    GenServer.call(__MODULE__, {:get, type, id})
  end

  @spec list(entity_type()) :: [attributes()]
  def list(type) do
    GenServer.call(__MODULE__, {:list, type})
  end

  @spec delete(entity_type(), entity_id()) :: :ok
  def delete(type, id) do
    GenServer.call(__MODULE__, {:delete, type, id})
  end

  @impl true
  def init(state), do: {:ok, state}

  @impl true
  def handle_call({:register, type, id, attrs}, _from, state) do
    updated =
      Map.update(state, type, %{id => attrs}, fn entries ->
        Map.put(entries, id, attrs)
      end)

    {:reply, :ok, updated}
  end

  def handle_call({:get, type, id}, _from, state) do
    case get_in(state, [type, id]) do
      nil -> {:reply, {:error, :not_found}, state}
      attrs -> {:reply, {:ok, attrs}, state}
    end
  end

  def handle_call({:list, type}, _from, state) do
    entries =
      state
      |> Map.get(type, %{})
      |> Map.values()

    {:reply, entries, state}
  end

  def handle_call({:delete, type, id}, _from, state) do
    updated =
      Map.update(state, type, %{}, fn entries ->
        Map.delete(entries, id)
      end)

    {:reply, :ok, updated}
  end
end
