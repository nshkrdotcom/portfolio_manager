defmodule PortfolioManager.Ports.Detection do
  @moduledoc """
  Port (behaviour) for repository detection.

  This defines the interface for detecting repository metadata
  like language, type, framework, etc.
  """

  @type detection_result :: %{
          language: atom() | nil,
          type: atom() | nil,
          framework: String.t() | nil,
          dependencies: [String.t()],
          confidence: float()
        }

  @doc """
  Detects metadata about a repository.
  """
  @callback detect(path :: String.t()) :: {:ok, detection_result()} | {:error, term()}

  @doc """
  Detects the primary programming language.
  """
  @callback detect_language(path :: String.t()) :: {:ok, atom()} | {:error, term()}

  @doc """
  Detects the repository type (library, app, etc).
  """
  @callback detect_type(path :: String.t()) :: {:ok, atom()} | {:error, term()}

  @doc """
  Detects dependencies from manifest files.
  """
  @callback detect_dependencies(path :: String.t()) :: {:ok, [String.t()]} | {:error, term()}

  @doc """
  Returns the configured detection adapter.
  """
  @spec adapter() :: module()
  def adapter do
    Application.get_env(
      :portfolio_manager,
      :detection_adapter,
      PortfolioManager.Adapters.FileDetector
    )
  end
end
