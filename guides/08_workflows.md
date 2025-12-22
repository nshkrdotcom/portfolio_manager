# Workflows

Workflows are YAML-defined multi-step automations. They can run against the
portfolio or a specific repo and can call git, shell, agentic, and update steps.

## Locations

Workflows are loaded from:

- Built-in workflows in `priv/workflows/`.
- User workflows in `$PORTFOLIO_DIR/workflows/`.

## Schema

```yaml
schema_version: 1

workflow:
  id: health-check
  name: "Portfolio Health Check"
  description: "Analyze repo health"
  version: 1.0.0
  target: portfolio
  inputs:
    scope:
      type: enum
      values: [all, active, stale]
      default: all
  outputs:
    report: $report
  steps:
    - id: get_all_repos
      type: context
      action: get_portfolio_context
      outputs:
        repos: portfolio_context

    - id: generate_report
      type: agent
      action: generate
      inputs:
        prompt: |
          Generate a portfolio health report.

          Repos: {{portfolio_context.repos}}
```

### Step fields

- `id`: optional; auto-generated if missing.
- `name`: optional display name.
- `type`: step type (git, shell, agent, file, context, update, control, workflow, detection).
- `action`: action within the type.
- `inputs`: inputs for the step (supports interpolation).
- `outputs`: map output keys to variable names.
- `when`: condition to run the step.
- `on_failure`: `stop` (default) or `continue`.
- `timeout`: milliseconds (default 60000).

## Interpolation and variables

- Use `{{inputs.repo_id}}` to interpolate values inside strings.
- Use `$inputs.repo_id` to pass a raw value (no string interpolation).
- Use `$results.step_id` or variables created via `outputs`.
- Built-in env variables live under `env.*` (HOME, USER, PWD, REPO_ID, REPO_PATH).

## Control flow

- `when` supports basic expressions (`==`, `!=`, `>`, `<`, `>=`, `<=`, `in`).
- `control` step with `action: condition` supports `on_true` / `on_false` branches.
- `control` step with `action: loop` iterates `items` and executes a nested `step`.

## Step types and actions

- `git`: `fetch`, `diff`, `log`, `clone`
- `shell`: `run`
- `agent`: `generate`, `analyze`, `classify`, `extract`
- `file`: `read`, `write`, `find_git_repos`
- `context`: `get_repo_context`, `get_related_context`, `get_portfolio_context`,
  `search_context`, `aggregate`, `validate_relationships`, `set_var`
- `update`: `update_context`, `add_relationship`, `create_decision`
- `control`: `condition`, `loop`, `abort`
- `workflow`: `run` (nested workflow)
- `detection`: `deterministic`, `agentic`

## Running workflows

```bash
mix portfolio.run --list
mix portfolio.run health-check
mix portfolio.run port-check --repo=my-port
mix portfolio.run health-check --dry-run --verbose
```
