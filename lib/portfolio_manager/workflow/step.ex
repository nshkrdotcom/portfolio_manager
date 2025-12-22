defmodule PortfolioManager.Workflow.Step do
  @moduledoc """
  Step execution for workflows.

  Routes step execution to appropriate step type handlers.
  """

  alias PortfolioManager.Workflow.Context

  alias PortfolioManager.Workflow.Steps.{
    GitStep,
    ShellStep,
    AgentStep,
    FileStep,
    ContextStep,
    UpdateStep,
    ControlStep,
    WorkflowStep,
    DetectionStep
  }

  @type step :: map()
  @type result :: {:ok, Context.t(), term()} | {:skip, term()} | {:error, term()}

  @doc """
  Executes a workflow step.
  """
  @spec execute(step(), Context.t(), keyword()) :: result()
  def execute(step, context, opts \\ [])

  def execute(%{when: condition} = step, context, opts) when not is_nil(condition) do
    if Context.evaluate_condition(context, condition) do
      do_execute(step, context, opts)
    else
      {:skip, "Condition not met: #{condition}"}
    end
  end

  def execute(%{type: :control} = step, context, opts) do
    ControlStep.execute(step, context, opts)
  end

  def execute(step, context, opts) do
    resolved_inputs = Context.resolve_inputs(context, Map.get(step, :inputs) || %{})
    step = Map.put(step, :inputs, resolved_inputs)
    do_execute(step, context, opts)
  end

  defp do_execute(%{type: :git} = step, context, opts) do
    GitStep.execute(step, context, opts)
  end

  defp do_execute(%{type: :shell} = step, context, opts) do
    ShellStep.execute(step, context, opts)
  end

  defp do_execute(%{type: :agent} = step, context, opts) do
    AgentStep.execute(step, context, opts)
  end

  defp do_execute(%{type: :file} = step, context, opts) do
    FileStep.execute(step, context, opts)
  end

  defp do_execute(%{type: :context} = step, context, opts) do
    ContextStep.execute(step, context, opts)
  end

  defp do_execute(%{type: :update} = step, context, opts) do
    UpdateStep.execute(step, context, opts)
  end

  defp do_execute(%{type: :workflow} = step, context, opts) do
    WorkflowStep.execute(step, context, opts)
  end

  defp do_execute(%{type: :detection} = step, context, opts) do
    DetectionStep.execute(step, context, opts)
  end

  defp do_execute(%{type: type}, _context, _opts) do
    {:error, {:unknown_step_type, type}}
  end
end
