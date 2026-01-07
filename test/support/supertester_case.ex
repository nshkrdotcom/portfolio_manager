defmodule PortfolioManager.SupertesterCase do
  @moduledoc """
  ExUnit case template with Supertester isolation and ETS table injection.
  """

  use ExUnit.CaseTemplate

  using opts do
    async? = Keyword.get(opts, :async, true)
    isolation = Keyword.get(opts, :isolation, :full_isolation)

    quote do
      use ExUnit.Case, async: unquote(async?)

      import Supertester.Assertions
      import Supertester.ETSIsolation
      import Supertester.GenServerHelpers
      import Supertester.OTPHelpers
      import PortfolioManager.SupertesterCase

      setup context do
        {:ok, base_context} =
          Supertester.UnifiedTestFoundation.setup_isolation(unquote(isolation), context)

        :ok = PortfolioManager.SupertesterCase.setup_ets_isolation()

        {:ok, %{isolation_context: base_context.isolation_context}}
      end
    end
  end

  @doc false
  def setup_ets_isolation do
    :ok = Supertester.ETSIsolation.setup_ets_isolation()

    {:ok, registry_table} =
      Supertester.ETSIsolation.create_isolated(:set, [
        :public,
        {:read_concurrency, true},
        {:write_concurrency, true}
      ])

    {:ok, _} =
      Supertester.ETSIsolation.inject_table(
        PortfolioCore.Registry,
        :table_name,
        registry_table,
        create: false
      )

    :ok
  end

  @doc false
  def safe_stop(nil), do: :ok

  def safe_stop(target) do
    try do
      GenServer.stop(target)
    catch
      :exit, _ -> :ok
    end

    :ok
  end
end
