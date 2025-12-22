defmodule PortfolioManager.CLI.Exit do
  @moduledoc """
  Exit helper for CLI tasks with design-specific exit codes.
  """

  @codes %{
    ok: 0,
    error: 1,
    invalid_args: 2,
    not_found: 3,
    config: 4,
    git: 5,
    agent: 6
  }

  @spec halt(atom() | non_neg_integer()) :: :ok
  def halt(code) do
    exit_code =
      case code do
        code when is_integer(code) -> code
        code when is_atom(code) -> Map.get(@codes, code, 1)
        _ -> 1
      end

    if test_env?() do
      :ok
    else
      System.halt(exit_code)
    end
  end

  defp test_env? do
    Code.ensure_loaded?(Mix) and function_exported?(Mix, :env, 0) and Mix.env() == :test
  end
end
