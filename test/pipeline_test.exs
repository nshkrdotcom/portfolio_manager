defmodule PortfolioManager.PipelineTest do
  use PortfolioManager.SupertesterCase, async: true

  import ExUnit.CaptureLog

  alias PortfolioManager.Pipeline

  describe "execute/2" do
    test "executes a simple pipeline" do
      pipeline = %Pipeline{
        name: :simple,
        steps: [
          %{
            name: :step1,
            function: fn _input -> {:ok, 1} end,
            depends_on: [],
            timeout: 5000,
            cache: false
          },
          %{
            name: :step2,
            function: fn input -> {:ok, input.deps.step1 + 1} end,
            depends_on: [:step1],
            timeout: 5000,
            cache: false
          }
        ],
        cache_table: :ets.new(:test_cache, [:set, :public]),
        results: %{}
      }

      assert {:ok, results} = Pipeline.execute(pipeline, %{})
      assert results.step1 == 1
      assert results.step2 == 2
    end

    test "executes steps in dependency order" do
      order_agent = Agent.start_link(fn -> [] end) |> elem(1)

      pipeline = %Pipeline{
        name: :ordered,
        steps: [
          %{
            name: :third,
            function: fn _input ->
              Agent.update(order_agent, &[:third | &1])
              {:ok, :done}
            end,
            depends_on: [:second],
            timeout: 5000,
            cache: false
          },
          %{
            name: :first,
            function: fn _input ->
              Agent.update(order_agent, &[:first | &1])
              {:ok, :done}
            end,
            depends_on: [],
            timeout: 5000,
            cache: false
          },
          %{
            name: :second,
            function: fn _input ->
              Agent.update(order_agent, &[:second | &1])
              {:ok, :done}
            end,
            depends_on: [:first],
            timeout: 5000,
            cache: false
          }
        ],
        cache_table: :ets.new(:order_cache, [:set, :public]),
        results: %{}
      }

      assert {:ok, _} = Pipeline.execute(pipeline, %{})

      order = Agent.get(order_agent, & &1) |> Enum.reverse()
      assert order == [:first, :second, :third]
    end

    test "passes context to steps" do
      pipeline = %Pipeline{
        name: :context,
        steps: [
          %{
            name: :use_context,
            function: fn input -> {:ok, input.value * 2} end,
            depends_on: [],
            timeout: 5000,
            cache: false
          }
        ],
        cache_table: :ets.new(:ctx_cache, [:set, :public]),
        results: %{}
      }

      assert {:ok, results} = Pipeline.execute(pipeline, %{value: 21})
      assert results.use_context == 42
    end

    test "handles step errors" do
      pipeline = %Pipeline{
        name: :errors,
        steps: [
          %{
            name: :failing,
            function: fn _input -> {:error, :something_wrong} end,
            depends_on: [],
            timeout: 5000,
            cache: false
          },
          %{
            name: :never_runs,
            function: fn _input -> {:ok, :unreachable} end,
            depends_on: [:failing],
            timeout: 5000,
            cache: false
          }
        ],
        cache_table: :ets.new(:error_cache, [:set, :public]),
        results: %{}
      }

      assert {:error, :something_wrong} = Pipeline.execute(pipeline, %{})
    end

    test "handles step timeouts" do
      pipeline = %Pipeline{
        name: :timeout,
        steps: [
          %{
            name: :slow,
            function: fn _input ->
              receive do
                :never -> {:ok, :never_returns}
              end
            end,
            depends_on: [],
            timeout: 50,
            cache: false
          }
        ],
        cache_table: :ets.new(:timeout_cache, [:set, :public]),
        results: %{}
      }

      assert {:error, {:timeout, :slow}} = Pipeline.execute(pipeline, %{})
    end

    test "caches step results" do
      call_count = Agent.start_link(fn -> 0 end) |> elem(1)
      cache_table = :ets.new(:caching_test, [:set, :public])

      pipeline = %Pipeline{
        name: :caching,
        steps: [
          %{
            name: :cached_step,
            function: fn _input ->
              Agent.update(call_count, &(&1 + 1))
              {:ok, :computed}
            end,
            depends_on: [],
            timeout: 5000,
            cache: true
          }
        ],
        cache_table: cache_table,
        results: %{}
      }

      # First execution
      assert {:ok, %{cached_step: :computed}} = Pipeline.execute(pipeline, %{key: 1})
      assert Agent.get(call_count, & &1) == 1

      # Second execution with same context should use cache
      assert {:ok, %{cached_step: :computed}} = Pipeline.execute(pipeline, %{key: 1})
      # Function should not be called again for same context hash
      assert Agent.get(call_count, & &1) == 1
    end

    test "emits telemetry events" do
      :telemetry.attach(
        "test-handler",
        [:portfolio_manager, :pipeline, :step_start],
        fn _event, _measurements, metadata, _config ->
          send(self(), {:step_start, metadata})
        end,
        nil
      )

      :telemetry.attach(
        "test-complete-handler",
        [:portfolio_manager, :pipeline, :step_complete],
        fn _event, _measurements, metadata, _config ->
          send(self(), {:step_complete, metadata})
        end,
        nil
      )

      on_exit(fn ->
        :telemetry.detach("test-handler")
        :telemetry.detach("test-complete-handler")
      end)

      pipeline = %Pipeline{
        name: :telemetry_test,
        steps: [
          %{
            name: :emit_step,
            function: fn _input -> {:ok, :done} end,
            depends_on: [],
            timeout: 5000,
            cache: false
          }
        ],
        cache_table: :ets.new(:tel_cache, [:set, :public]),
        results: %{}
      }

      Pipeline.execute(pipeline, %{})

      assert_receive {:step_start, %{pipeline: :telemetry_test, step: :emit_step}}
      assert_receive {:step_complete, %{pipeline: :telemetry_test, step: :emit_step}}
    end
  end

  describe "run/3 macro" do
    test "defines and executes a pipeline" do
      import Pipeline

      result =
        run(:macro_test, %{initial: 10}) do
          step(:double, fn input -> input.initial * 2 end)
          step(:add_ten, fn input -> input.deps.double + 10 end, depends_on: [:double])
        end

      assert {:ok, results} = result
      assert results.double == 20
      assert results.add_ten == 30
    end
  end

  describe "new/2" do
    test "creates a pipeline with options" do
      pipeline =
        Pipeline.new(:test_pipeline,
          description: "A test pipeline",
          config: %{max_retries: 3},
          metadata: %{user: "test"}
        )

      assert pipeline.name == :test_pipeline
      assert pipeline.description == "A test pipeline"
      assert pipeline.config == %{max_retries: 3}
      assert pipeline.metadata == %{user: "test"}
    end
  end

  describe "add_step/4" do
    test "adds step to pipeline" do
      pipeline = Pipeline.new(:test)
      pipeline = Pipeline.add_step(pipeline, :first, fn _ -> {:ok, 1} end)

      assert length(pipeline.steps) == 1
      [step] = pipeline.steps
      assert step.name == :first
    end

    test "adds step with options" do
      pipeline = Pipeline.new(:test)

      pipeline =
        Pipeline.add_step(pipeline, :step1, fn _ -> {:ok, 1} end,
          parallel: true,
          on_error: :continue,
          timeout: 5000
        )

      [step] = pipeline.steps
      assert step.parallel == true
      assert step.on_error == :continue
      assert step.timeout == 5000
    end
  end

  describe "parallel execution" do
    test "executes parallel steps concurrently" do
      parent = self()

      pipeline =
        Pipeline.new(:parallel_test)
        |> Pipeline.add_step(
          :step_a,
          fn _input ->
            send(parent, {:step_start, :a, self()})

            receive do
              {:continue, :a} -> :ok
            end

            send(parent, {:step_end, :a})
            {:ok, :a}
          end,
          parallel: true
        )
        |> Pipeline.add_step(
          :step_b,
          fn _input ->
            send(parent, {:step_start, :b, self()})

            receive do
              {:continue, :b} -> :ok
            end

            send(parent, {:step_end, :b})
            {:ok, :b}
          end,
          parallel: true
        )

      task = Task.async(fn -> Pipeline.execute(pipeline, %{}) end)

      assert_receive {:step_start, :a, pid_a}, 500
      assert_receive {:step_start, :b, pid_b}, 500

      send(pid_a, {:continue, :a})
      send(pid_b, {:continue, :b})

      assert_receive {:step_end, :a}, 500
      assert_receive {:step_end, :b}, 500

      assert {:ok, results} = Task.await(task, 1000)
      assert results.step_a == :a
      assert results.step_b == :b
    end
  end

  describe "on_error policies" do
    test "halt stops pipeline on error (default)" do
      pipeline =
        Pipeline.new(:halt_test)
        |> Pipeline.add_step(:failing, fn _ -> {:error, :something_wrong} end, on_error: :halt)
        |> Pipeline.add_step(:never_runs, fn _ -> {:ok, :unreachable} end, depends_on: [:failing])

      assert {:error, :something_wrong} = Pipeline.execute(pipeline, %{})
    end

    test "continue proceeds despite errors" do
      pipeline =
        Pipeline.new(:continue_test)
        |> Pipeline.add_step(:failing, fn _ -> {:error, :oops} end, on_error: :continue)
        |> Pipeline.add_step(
          :next,
          fn input ->
            {:ok, {:failed_step_result, input.deps.failing}}
          end,
          depends_on: [:failing]
        )

      capture_log(fn ->
        assert {:ok, results} = Pipeline.execute(pipeline, %{})
        assert results.failing == {:error, :oops}
        assert results.next == {:failed_step_result, {:error, :oops}}
      end)
    end

    test "retry attempts step multiple times" do
      call_count = Agent.start_link(fn -> 0 end) |> elem(1)

      pipeline =
        Pipeline.new(:retry_test)
        |> Pipeline.add_step(
          :flaky,
          fn _ ->
            count = Agent.get_and_update(call_count, &{&1 + 1, &1 + 1})

            if count < 3 do
              {:error, :temporary_failure}
            else
              {:ok, :success}
            end
          end,
          on_error: {:retry, 3}
        )

      capture_log(fn ->
        assert {:ok, results} = Pipeline.execute(pipeline, %{})
        assert results.flaky == :success
        assert Agent.get(call_count, & &1) == 3
      end)
    end

    test "retry exhaustion returns error" do
      pipeline =
        Pipeline.new(:retry_fail_test)
        |> Pipeline.add_step(
          :always_fails,
          fn _ ->
            {:error, :permanent_failure}
          end,
          on_error: {:retry, 2}
        )

      capture_log(fn ->
        assert {:error, :permanent_failure} = Pipeline.execute(pipeline, %{})
      end)
    end
  end

  describe "parallel with on_error" do
    test "parallel steps with continue policy" do
      pipeline =
        Pipeline.new(:parallel_continue)
        |> Pipeline.add_step(:good, fn _ -> {:ok, :success} end, parallel: true)
        |> Pipeline.add_step(:bad, fn _ -> {:error, :failed} end,
          parallel: true,
          on_error: :continue
        )

      capture_log(fn ->
        assert {:ok, results} = Pipeline.execute(pipeline, %{})
        assert results.good == :success
        assert results.bad == {:error, :failed}
      end)
    end
  end
end
