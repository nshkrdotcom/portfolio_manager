defmodule PortfolioManager.Ports.Git do
  @moduledoc """
  Port (behaviour) for Git operations.

  This defines the interface for interacting with git repositories.
  """

  @type repo_info :: %{
          path: String.t(),
          remote_url: String.t() | nil,
          branch: String.t() | nil,
          last_commit: String.t() | nil,
          last_commit_date: DateTime.t() | nil,
          is_dirty: boolean()
        }

  @doc """
  Checks if a path is a git repository.
  """
  @callback is_repo?(path :: String.t()) :: boolean()

  @doc """
  Gets information about a git repository.
  """
  @callback get_info(path :: String.t()) :: {:ok, repo_info()} | {:error, term()}

  @doc """
  Gets the remote URL for a repository.
  """
  @callback get_remote_url(path :: String.t()) :: {:ok, String.t()} | {:error, term()}

  @doc """
  Commits changes to the repository.
  """
  @callback commit(path :: String.t(), message :: String.t()) :: :ok | {:error, term()}

  @doc """
  Stages all changes in the repository.
  """
  @callback add_all(path :: String.t()) :: :ok | {:error, term()}

  @doc """
  Checks if there are uncommitted changes.
  """
  @callback is_dirty?(path :: String.t()) :: boolean()

  @doc """
  Returns the configured git adapter.
  """
  @spec adapter() :: module()
  def adapter do
    Application.get_env(:portfolio_manager, :git_adapter, PortfolioManager.Adapters.LocalGit)
  end
end
