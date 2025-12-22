defmodule PortfolioManager.Workflow.EngineTest do
  use ExUnit.Case, async: true

  import PortfolioManager.TestHelpers

  alias PortfolioManager.Workflow.{Engine, Parser}

  test "parser reads workflow root schema" do
    yaml = """
    schema_version: 1
    workflow:
      id: test-workflow
      name: "Test Workflow"
      description: "Test description"
      inputs:
        repo_id:
          type: string
          required: true
      steps:
        - id: get_context
          type: context
          action: get_repo_context
          inputs:
            repo_id: $inputs.repo_id
          outputs:
            context: repo_context
    """

    assert {:ok, workflow} = Parser.parse_string(yaml)
    assert workflow.id == "test-workflow"
    assert workflow.name == "Test Workflow"
    assert length(workflow.steps) == 1
    assert hd(workflow.steps).type == :context
    assert hd(workflow.steps).action == "get_repo_context"
  end

  test "engine executes control condition and update step" do
    portfolio_path = create_test_portfolio()
    repo_path = Path.join(System.tmp_dir!(), "workflow_repo_#{:rand.uniform(1_000_000)}")

    create_test_repo(repo_path, name: "workflow_repo", language: :elixir)

    {:ok, portfolio} = PortfolioManager.init(portfolio_path)
    {:ok, repo} = PortfolioManager.add(portfolio, repo_path)

    workflows_dir = Path.join(portfolio_path, "workflows")
    File.mkdir_p!(workflows_dir)

    workflow_path = Path.join(workflows_dir, "test-flow.yml")

    File.write!(
      workflow_path,
      """
      schema_version: 1
      workflow:
        id: test-flow
        name: "Test Flow"
        inputs:
          repo_id:
            type: string
            required: true
        steps:
          - id: get_context
            type: context
            action: get_repo_context
            inputs:
              repo_id: $inputs.repo_id
            outputs:
              context: repo_context

          - id: check_active
            type: control
            action: condition
            inputs:
              condition: "$repo_context.status == \\"active\\""
              on_true:
                - id: mark
                  type: update
                  action: update_context
                  inputs:
                    repo_id: $inputs.repo_id
                    updates:
                      status: maintenance
      """
    )

    System.put_env("PORTFOLIO_DIR", portfolio_path)

    on_exit(fn ->
      System.delete_env("PORTFOLIO_DIR")
      cleanup_test_portfolio(portfolio_path)
      cleanup_test_repo(repo_path)
    end)

    assert {:ok, result} =
             Engine.run("test-flow", portfolio: portfolio, inputs: %{"repo_id" => repo.id})

    assert result.completed >= 2
    assert :ok = PortfolioManager.sync(portfolio)

    {:ok, portfolio_after} = PortfolioManager.init(portfolio_path)
    {:ok, context} = PortfolioManager.get_context(portfolio_after, repo.id)
    assert context.repo.status == :maintenance
  end
end
