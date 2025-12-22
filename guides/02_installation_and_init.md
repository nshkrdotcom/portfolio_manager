# Installation and Initialization

This guide shows how to install the library, set the portfolio location, and
bootstrap a new portfolio repo.

## Install the Library

Add the dependency in `mix.exs`:

```elixir
def deps do
  [
    {:portfolio_manager, "~> 0.1.0"}
  ]
end
```

Then:

```bash
mix deps.get
```

## Choose a Portfolio Location

By default, the CLI uses `~/portfolio`. For centralized setups, set `PORTFOLIO_DIR`:

```bash
export PORTFOLIO_DIR=~/p/g/n/portfolio
```

You can also configure a default in `config/config.exs`:

```elixir
config :portfolio_manager,
  portfolio_path: "~/p/g/n/portfolio"
```

## Initialize the Portfolio

```bash
mix portfolio.init
```

This creates:

```
portfolio/
|-- config.yml
|-- registry.yml
|-- relationships.yml
`-- repos/
```

The `.portfolio/` directory will be created on demand for cache and review state.

## Configure Scan Directories

Edit `config.yml` to add your working directories:

```yaml
version: "1.0"
scan:
  directories:
    - ~/p/g/n
    - ~/p/g/other
  exclude_patterns:
    - "**/node_modules/**"
    - "**/.git/**"
    - "**/deps/**"
    - "**/_build/**"
```

You can also use the CLI helpers:

```bash
mix portfolio.config list-dirs
mix portfolio.config add-dir ~/p/g/n
mix portfolio.config remove-dir ~/p/g/old
```

## First Scan

```bash
mix portfolio.scan
```

If you want agentic detection in the same pass:

```bash
mix portfolio.scan --agentic --review
```

The next guide walks through the CLI workflow in detail.
