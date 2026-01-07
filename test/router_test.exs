defmodule PortfolioManager.RouterTest do
  use PortfolioManager.SupertesterCase, async: false

  import ExUnit.CaptureLog

  import Mox

  alias PortfolioManager.Router

  setup :verify_on_exit!

  setup do
    # Stop any existing router started by the application
    case Process.whereis(Router) do
      nil -> :ok
      pid -> safe_stop(pid)
    end

    :ok
  end

  describe "start_link/1" do
    test "starts the router with default options" do
      assert {:ok, pid} = Router.start_link([])
      assert Process.alive?(pid)
      safe_stop(pid)
    end

    test "starts with custom strategy" do
      assert {:ok, pid} = Router.start_link(strategy: :round_robin)
      assert Router.get_strategy() == :round_robin
      safe_stop(pid)
    end

    test "starts with providers" do
      providers = [
        %{
          name: :test_provider,
          module: PortfolioManager.Mocks.LLM,
          config: %{},
          capabilities: [:generation],
          priority: 1
        }
      ]

      assert {:ok, pid} = Router.start_link(providers: providers)
      assert length(Router.list_providers()) == 1
      safe_stop(pid)
    end
  end

  describe "complete/2" do
    setup do
      {:ok, pid} =
        Router.start_link(
          strategy: :fallback,
          providers: [
            %{
              name: :test_llm,
              module: PortfolioManager.Mocks.LLM,
              config: %{model: "test"},
              capabilities: [:generation, :reasoning],
              priority: 1
            }
          ],
          health_check_interval: 0
        )

      on_exit(fn ->
        if Process.alive?(pid), do: safe_stop(pid)
      end)

      :ok
    end

    test "routes to healthy provider" do
      PortfolioManager.Mocks.LLM
      |> expect(:complete, fn messages, _opts ->
        assert length(messages) == 1
        {:ok, %{content: "test response", usage: %{input_tokens: 5, output_tokens: 3}}}
      end)

      assert {:ok, %{content: "test response"}} =
               Router.complete([%{role: :user, content: "test"}])
    end

    test "returns error when no healthy providers" do
      # Stop the router started by describe setup
      case Process.whereis(Router) do
        nil -> :ok
        pid -> safe_stop(pid)
      end

      {:ok, pid} = Router.start_link(strategy: :fallback, providers: [])
      on_exit(fn -> if Process.alive?(pid), do: safe_stop(pid) end)

      assert {:error, :no_healthy_providers} =
               Router.complete([%{role: :user, content: "test"}])
    end
  end

  describe "stream/3" do
    setup do
      {:ok, pid} =
        Router.start_link(
          strategy: :fallback,
          providers: [
            %{
              name: :stream_llm,
              module: PortfolioManager.Mocks.LLM,
              config: %{},
              capabilities: [:generation],
              priority: 1
            }
          ],
          health_check_interval: 0
        )

      on_exit(fn ->
        if Process.alive?(pid), do: safe_stop(pid)
      end)

      :ok
    end

    test "streams response through callback" do
      chunks = ["Hello", " ", "World"]

      PortfolioManager.Mocks.LLM
      |> expect(:stream, fn messages, _opts ->
        assert length(messages) == 1
        # stream/2 returns {:ok, enumerable}
        {:ok, chunks}
      end)

      received = Agent.start_link(fn -> [] end) |> elem(1)

      callback = fn chunk ->
        Agent.update(received, &[chunk | &1])
      end

      assert :ok = Router.stream([%{role: :user, content: "test"}], callback)

      result = Agent.get(received, & &1) |> Enum.reverse()
      assert result == chunks
    end
  end

  describe "strategies" do
    test "fallback uses first healthy provider by priority" do
      {:ok, pid} =
        Router.start_link(
          strategy: :fallback,
          providers: [
            %{
              name: :second,
              module: PortfolioManager.Mocks.LLM,
              config: %{},
              capabilities: [:generation],
              priority: 2
            },
            %{
              name: :first,
              module: PortfolioManager.Mocks.LLM,
              config: %{},
              capabilities: [:generation],
              priority: 1
            }
          ],
          health_check_interval: 0
        )

      on_exit(fn -> if Process.alive?(pid), do: safe_stop(pid) end)

      PortfolioManager.Mocks.LLM
      |> expect(:complete, fn _msgs, _opts ->
        {:ok, %{content: "from first"}}
      end)

      assert {:ok, %{content: "from first"}} =
               Router.complete([%{role: :user, content: "test"}])
    end

    test "round_robin distributes requests" do
      {:ok, pid} =
        Router.start_link(
          strategy: :round_robin,
          providers: [
            %{
              name: :provider_a,
              module: PortfolioManager.Mocks.LLM,
              config: %{id: :a},
              capabilities: [:generation],
              priority: 1
            },
            %{
              name: :provider_b,
              module: PortfolioManager.Mocks.LLM,
              config: %{id: :b},
              capabilities: [:generation],
              priority: 2
            }
          ],
          health_check_interval: 0
        )

      on_exit(fn -> if Process.alive?(pid), do: safe_stop(pid) end)

      PortfolioManager.Mocks.LLM
      |> expect(:complete, 2, fn _msgs, _opts ->
        {:ok, %{content: "response"}}
      end)

      # First call
      assert {:ok, _} = Router.complete([%{role: :user, content: "test"}])
      # Second call should go to different provider
      assert {:ok, _} = Router.complete([%{role: :user, content: "test"}])
    end

    test "specialist routes by capability" do
      {:ok, pid} =
        Router.start_link(
          strategy: :specialist,
          providers: [
            %{
              name: :general,
              module: PortfolioManager.Mocks.LLM,
              config: %{},
              capabilities: [:generation],
              priority: 2
            },
            %{
              name: :code_expert,
              module: PortfolioManager.Mocks.LLM,
              config: %{},
              capabilities: [:code, :generation],
              priority: 1
            }
          ],
          health_check_interval: 0
        )

      on_exit(fn -> if Process.alive?(pid), do: safe_stop(pid) end)

      PortfolioManager.Mocks.LLM
      |> expect(:complete, fn _msgs, _opts ->
        {:ok, %{content: "code response"}}
      end)

      assert {:ok, %{content: "code response"}} =
               Router.complete([%{role: :user, content: "fix this"}], task_type: :code)
    end

    test "cost_optimized routes to cheapest provider" do
      {:ok, pid} =
        Router.start_link(
          strategy: :cost_optimized,
          providers: [
            %{
              name: :expensive,
              module: PortfolioManager.Mocks.LLM,
              config: %{},
              capabilities: [:generation],
              priority: 1,
              cost_per_token: 0.01
            },
            %{
              name: :cheap,
              module: PortfolioManager.Mocks.LLM,
              config: %{},
              capabilities: [:generation],
              priority: 2,
              cost_per_token: 0.001
            }
          ],
          health_check_interval: 0
        )

      on_exit(fn -> if Process.alive?(pid), do: safe_stop(pid) end)

      PortfolioManager.Mocks.LLM
      |> expect(:complete, fn _msgs, _opts ->
        {:ok, %{content: "cheap response"}}
      end)

      assert {:ok, _} = Router.complete([%{role: :user, content: "test"}])
    end
  end

  describe "register_provider/1" do
    test "adds a new provider" do
      {:ok, pid} = Router.start_link(providers: [])
      on_exit(fn -> if Process.alive?(pid), do: safe_stop(pid) end)

      assert :ok =
               Router.register_provider(%{
                 name: :new_provider,
                 module: PortfolioManager.Mocks.LLM,
                 config: %{},
                 capabilities: [:generation],
                 priority: 1
               })

      assert length(Router.list_providers()) == 1
    end
  end

  describe "health_check/1" do
    test "returns health status of provider" do
      {:ok, pid} =
        Router.start_link(
          providers: [
            %{
              name: :test,
              module: PortfolioManager.Mocks.LLM,
              config: %{},
              capabilities: [:generation],
              priority: 1
            }
          ],
          health_check_interval: 0
        )

      on_exit(fn -> if Process.alive?(pid), do: safe_stop(pid) end)

      assert Router.health_check(:test) == :healthy
      assert Router.health_check(:unknown) == :unknown
    end
  end

  describe "get_strategy/0 and set_strategy/1" do
    test "can get and set strategy" do
      {:ok, pid} = Router.start_link(strategy: :fallback)
      on_exit(fn -> if Process.alive?(pid), do: safe_stop(pid) end)

      assert Router.get_strategy() == :fallback

      assert :ok = Router.set_strategy(:round_robin)
      assert Router.get_strategy() == :round_robin
    end
  end

  describe "route/2" do
    test "returns selected provider without executing" do
      {:ok, pid} =
        Router.start_link(
          strategy: :fallback,
          providers: [
            %{
              name: :test_llm,
              module: PortfolioManager.Mocks.LLM,
              config: %{},
              capabilities: [:generation],
              priority: 1
            }
          ],
          health_check_interval: 0
        )

      on_exit(fn -> if Process.alive?(pid), do: safe_stop(pid) end)

      assert {:ok, provider} = Router.route([%{role: :user, content: "test"}])
      assert provider.name == :test_llm
    end
  end

  describe "execute/2" do
    test "routes and executes in one call" do
      {:ok, pid} =
        Router.start_link(
          strategy: :fallback,
          providers: [
            %{
              name: :test_llm,
              module: PortfolioManager.Mocks.LLM,
              config: %{},
              capabilities: [:generation],
              priority: 1
            }
          ],
          health_check_interval: 0
        )

      on_exit(fn -> if Process.alive?(pid), do: safe_stop(pid) end)

      PortfolioManager.Mocks.LLM
      |> expect(:complete, fn _msgs, _opts ->
        {:ok, %{content: "response"}}
      end)

      assert {:ok, %{content: "response"}} =
               Router.execute([%{role: :user, content: "test"}])
    end
  end

  describe "execute_with_retry/2" do
    test "retries on failure" do
      {:ok, pid} =
        Router.start_link(
          strategy: :fallback,
          providers: [
            %{
              name: :test_llm,
              module: PortfolioManager.Mocks.LLM,
              config: %{},
              capabilities: [:generation],
              priority: 1
            }
          ],
          health_check_interval: 0
        )

      on_exit(fn -> if Process.alive?(pid), do: safe_stop(pid) end)

      # First call fails, second succeeds
      PortfolioManager.Mocks.LLM
      |> expect(:complete, fn _msgs, _opts -> {:error, :rate_limited} end)
      |> expect(:complete, fn _msgs, _opts -> {:ok, %{content: "success"}} end)

      capture_log(fn ->
        assert {:ok, %{content: "success"}} =
                 Router.execute_with_retry(
                   [%{role: :user, content: "test"}],
                   max_retries: 2,
                   retry_delay: 1
                 )
      end)
    end

    test "returns error after all retries exhausted" do
      {:ok, pid} =
        Router.start_link(
          strategy: :fallback,
          providers: [
            %{
              name: :test_llm,
              module: PortfolioManager.Mocks.LLM,
              config: %{},
              capabilities: [:generation],
              priority: 1
            }
          ],
          health_check_interval: 0
        )

      on_exit(fn -> if Process.alive?(pid), do: safe_stop(pid) end)

      PortfolioManager.Mocks.LLM
      |> expect(:complete, 2, fn _msgs, _opts -> {:error, :rate_limited} end)

      capture_log(fn ->
        assert {:error, {:all_providers_failed, _}} =
                 Router.execute_with_retry(
                   [%{role: :user, content: "test"}],
                   max_retries: 2,
                   retry_delay: 1
                 )
      end)
    end
  end

  describe "report_result/3" do
    test "tracks failures and marks provider unhealthy after threshold" do
      {:ok, pid} =
        Router.start_link(
          strategy: :fallback,
          providers: [
            %{
              name: :flaky,
              module: PortfolioManager.Mocks.LLM,
              config: %{},
              capabilities: [:generation],
              priority: 1
            }
          ],
          failure_threshold: 2,
          health_check_interval: 0
        )

      on_exit(fn -> if Process.alive?(pid), do: safe_stop(pid) end)

      assert Router.health_check(:flaky) == :healthy

      Router.report_result(:flaky, :failure, %{})
      assert Router.health_check(:flaky) == :healthy

      Router.report_result(:flaky, :failure, %{})
      assert Router.health_check(:flaky) == :unhealthy
    end

    test "resets failure count on success" do
      {:ok, pid} =
        Router.start_link(
          strategy: :fallback,
          providers: [
            %{
              name: :test,
              module: PortfolioManager.Mocks.LLM,
              config: %{},
              capabilities: [:generation],
              priority: 1
            }
          ],
          failure_threshold: 3,
          health_check_interval: 0
        )

      on_exit(fn -> if Process.alive?(pid), do: safe_stop(pid) end)

      Router.report_result(:test, :failure, %{})
      Router.report_result(:test, :failure, %{})
      Router.report_result(:test, :success, %{})
      Router.report_result(:test, :failure, %{})
      Router.report_result(:test, :failure, %{})

      assert Router.health_check(:test) == :healthy
    end
  end

  describe "next_provider/2" do
    test "returns next provider after current" do
      {:ok, pid} =
        Router.start_link(
          strategy: :fallback,
          providers: [
            %{
              name: :first,
              module: PortfolioManager.Mocks.LLM,
              config: %{},
              capabilities: [:generation],
              priority: 1
            },
            %{
              name: :second,
              module: PortfolioManager.Mocks.LLM,
              config: %{},
              capabilities: [:generation],
              priority: 2
            }
          ],
          health_check_interval: 0
        )

      on_exit(fn -> if Process.alive?(pid), do: safe_stop(pid) end)

      assert {:ok, provider} = Router.next_provider(:first)
      assert provider.name == :second
    end

    test "returns error when no more providers" do
      {:ok, pid} =
        Router.start_link(
          strategy: :fallback,
          providers: [
            %{
              name: :only,
              module: PortfolioManager.Mocks.LLM,
              config: %{},
              capabilities: [:generation],
              priority: 1
            }
          ],
          health_check_interval: 0
        )

      on_exit(fn -> if Process.alive?(pid), do: safe_stop(pid) end)

      assert {:error, :no_more} = Router.next_provider(:only)
    end
  end

  describe "get_provider/1" do
    test "returns provider by name" do
      {:ok, pid} =
        Router.start_link(
          providers: [
            %{
              name: :mytest,
              module: PortfolioManager.Mocks.LLM,
              config: %{model: "test"},
              capabilities: [:generation],
              priority: 1
            }
          ],
          health_check_interval: 0
        )

      on_exit(fn -> if Process.alive?(pid), do: safe_stop(pid) end)

      assert {:ok, provider} = Router.get_provider(:mytest)
      assert provider.config.model == "test"
    end

    test "returns error for unknown provider" do
      {:ok, pid} = Router.start_link(providers: [], health_check_interval: 0)
      on_exit(fn -> if Process.alive?(pid), do: safe_stop(pid) end)

      assert {:error, :not_found} = Router.get_provider(:unknown)
    end
  end

  describe "unregister_provider/1" do
    test "removes a provider" do
      {:ok, pid} =
        Router.start_link(
          providers: [
            %{
              name: :removable,
              module: PortfolioManager.Mocks.LLM,
              config: %{},
              capabilities: [:generation],
              priority: 1
            }
          ],
          health_check_interval: 0
        )

      on_exit(fn -> if Process.alive?(pid), do: safe_stop(pid) end)

      assert [_] = Router.list_providers()
      assert :ok = Router.unregister_provider(:removable)
      assert [] = Router.list_providers()
    end
  end
end
