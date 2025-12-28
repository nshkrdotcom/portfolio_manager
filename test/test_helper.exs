ExUnit.start()

case Process.whereis(PortfolioCore.Registry) do
  nil ->
    {:ok, _} = PortfolioCore.Registry.start_link([])

  _pid ->
    :ok
end
