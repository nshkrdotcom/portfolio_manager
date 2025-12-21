defmodule PortfolioManager.Ports.Storage do
  @moduledoc """
  Port (behaviour) for storage operations.

  This defines the interface for persisting and loading portfolio data.
  """

  alias PortfolioManager.Domain.{Context, Registry}

  @doc """
  Initializes the storage at the given path.
  """
  @callback init(path :: String.t()) :: {:ok, term()} | {:error, term()}

  @doc """
  Loads the registry from storage.
  """
  @callback load_registry(state :: term()) :: {:ok, Registry.t()} | {:error, term()}

  @doc """
  Saves the registry to storage.
  """
  @callback save_registry(state :: term(), registry :: Registry.t()) :: :ok | {:error, term()}

  @doc """
  Loads context for a specific repo.
  """
  @callback load_context(state :: term(), repo_id :: String.t()) ::
              {:ok, Context.t()} | {:error, term()}

  @doc """
  Saves context for a specific repo.
  """
  @callback save_context(state :: term(), context :: Context.t()) :: :ok | {:error, term()}

  @doc """
  Checks if the storage exists and is initialized.
  """
  @callback exists?(path :: String.t()) :: boolean()

  @doc """
  Creates the initial storage structure.
  """
  @callback create(path :: String.t()) :: :ok | {:error, term()}

  @doc """
  Returns the configured storage adapter.
  """
  @spec adapter() :: module()
  def adapter do
    Application.get_env(
      :portfolio_manager,
      :storage_adapter,
      PortfolioManager.Adapters.YAMLStorage
    )
  end
end
