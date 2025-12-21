defmodule Mix.Tasks.Portfolio.Completion do
  @moduledoc """
  Generate shell completion scripts.

  ## Usage

      mix portfolio.completion <shell>

  ## Supported Shells

    * `bash` - Bash completion
    * `zsh` - Zsh completion
    * `fish` - Fish shell completion

  ## Examples

      # Generate bash completion
      mix portfolio.completion bash > ~/.portfolio_completion.bash
      echo 'source ~/.portfolio_completion.bash' >> ~/.bashrc

      # Generate zsh completion
      mix portfolio.completion zsh > ~/.portfolio_completion.zsh
      echo 'source ~/.portfolio_completion.zsh' >> ~/.zshrc

      # Generate fish completion
      mix portfolio.completion fish > ~/.config/fish/completions/portfolio.fish

  """
  @shortdoc "Generate shell completion scripts"

  use Mix.Task

  @commands ~w(init scan add remove list show edit search sync status ask run config completion repl)
  @statuses ~w(active maintenance stale blocked archived)
  @types ~w(library application port fork experiment template config docs)
  @languages ~w(elixir python javascript rust go ruby java cpp)

  @impl Mix.Task
  def run(args) do
    case args do
      ["bash"] -> generate_bash()
      ["zsh"] -> generate_zsh()
      ["fish"] -> generate_fish()
      ["--help"] -> show_help()
      [] -> show_help()
      _ -> show_help()
    end
  end

  defp generate_bash do
    script = """
    # Portfolio Manager Bash Completion
    # Add to ~/.bashrc: source ~/.portfolio_completion.bash

    _portfolio_completion() {
        local cur prev commands
        COMPREPLY=()
        cur="${COMP_WORDS[COMP_CWORD]}"
        prev="${COMP_WORDS[COMP_CWORD-1]}"

        commands="#{Enum.join(@commands, " ")}"
        statuses="#{Enum.join(@statuses, " ")}"
        types="#{Enum.join(@types, " ")}"
        languages="#{Enum.join(@languages, " ")}"

        # Complete mix portfolio.* commands
        if [[ ${COMP_WORDS[1]} == "portfolio."* ]]; then
            local subcmd="${COMP_WORDS[1]#portfolio.}"

            case "$subcmd" in
                list)
                    case "$prev" in
                        --status|-s)
                            COMPREPLY=( $(compgen -W "$statuses" -- "$cur") )
                            return 0
                            ;;
                        --type|-t)
                            COMPREPLY=( $(compgen -W "$types" -- "$cur") )
                            return 0
                            ;;
                        --language|-l)
                            COMPREPLY=( $(compgen -W "$languages" -- "$cur") )
                            return 0
                            ;;
                    esac
                    COMPREPLY=( $(compgen -W "--status --type --language --json --help" -- "$cur") )
                    ;;
                edit)
                    case "$prev" in
                        --status|-s)
                            COMPREPLY=( $(compgen -W "$statuses" -- "$cur") )
                            return 0
                            ;;
                        --type|-t)
                            COMPREPLY=( $(compgen -W "$types" -- "$cur") )
                            return 0
                            ;;
                        --priority)
                            COMPREPLY=( $(compgen -W "high medium low" -- "$cur") )
                            return 0
                            ;;
                    esac
                    COMPREPLY=( $(compgen -W "--type --status --purpose --tags --priority --note --decision --json --help" -- "$cur") )
                    ;;
                run)
                    if [[ "$prev" == "run" || "$prev" == "portfolio.run" ]]; then
                        COMPREPLY=( $(compgen -W "port-check port-sync health-check doc-generate initial-setup --list" -- "$cur") )
                    else
                        COMPREPLY=( $(compgen -W "--repo --dry-run --verbose --list --json --help" -- "$cur") )
                    fi
                    ;;
                sync)
                    COMPREPLY=( $(compgen -W "--all --views --json --help" -- "$cur") )
                    ;;
                config)
                    if [[ "$prev" == "config" || "$prev" == "portfolio.config" ]]; then
                        COMPREPLY=( $(compgen -W "show get set list-dirs add-dir remove-dir" -- "$cur") )
                    else
                        COMPREPLY=( $(compgen -W "--json --help" -- "$cur") )
                    fi
                    ;;
                completion)
                    COMPREPLY=( $(compgen -W "bash zsh fish" -- "$cur") )
                    ;;
                *)
                    COMPREPLY=( $(compgen -W "--help" -- "$cur") )
                    ;;
            esac
            return 0
        fi

        # Complete portfolio.* subcommands
        if [[ "$cur" == portfolio.* ]]; then
            local prefix="portfolio."
            COMPREPLY=( $(compgen -W "$(printf '%s\\n' ${commands[@]/#/$prefix})" -- "$cur") )
            return 0
        fi

        return 0
    }

    complete -F _portfolio_completion mix
    """

    IO.puts(script)
  end

  defp generate_zsh do
    script = """
    #compdef mix

    # Portfolio Manager Zsh Completion
    # Add to ~/.zshrc: source ~/.portfolio_completion.zsh

    _portfolio_commands() {
        local commands=(
            'init:Initialize a new portfolio'
            'scan:Scan directories for repositories'
            'add:Add a repository'
            'remove:Remove a repository'
            'list:List repositories'
            'show:Show repository details'
            'edit:Edit repository metadata'
            'search:Search repositories'
            'sync:Synchronize portfolio'
            'status:Show portfolio status'
            'ask:Ask questions about portfolio'
            'run:Run a workflow'
            'config:Manage configuration'
            'completion:Generate shell completions'
            'repl:Start interactive mode'
        )
        _describe 'command' commands
    }

    _portfolio_statuses() {
        local statuses=(#{Enum.map_join(@statuses, " ", &"'#{&1}'")})
        _describe 'status' statuses
    }

    _portfolio_types() {
        local types=(#{Enum.map_join(@types, " ", &"'#{&1}'")})
        _describe 'type' types
    }

    _portfolio_workflows() {
        local workflows=(
            'port-check:Check port status'
            'port-sync:Sync port with upstream'
            'health-check:Run health checks'
            'doc-generate:Generate documentation'
            'initial-setup:Initial repository setup'
        )
        _describe 'workflow' workflows
    }

    _portfolio() {
        local line
        _arguments -C \\
            "1: :_portfolio_commands" \\
            "*::arg:->args"

        case $line[1] in
            list)
                _arguments \\
                    '--status[Filter by status]:status:_portfolio_statuses' \\
                    '--type[Filter by type]:type:_portfolio_types' \\
                    '--language[Filter by language]' \\
                    '--json[Output as JSON]' \\
                    '--help[Show help]'
                ;;
            edit)
                _arguments \\
                    '--type[Set type]:type:_portfolio_types' \\
                    '--status[Set status]:status:_portfolio_statuses' \\
                    '--purpose[Set purpose]' \\
                    '--tags[Set tags]' \\
                    '--priority[Set priority]:(high medium low)' \\
                    '--json[Output as JSON]' \\
                    '--help[Show help]'
                ;;
            run)
                _arguments \\
                    "1: :_portfolio_workflows" \\
                    '--repo[Target repository]' \\
                    '--dry-run[Dry run mode]' \\
                    '--verbose[Verbose output]' \\
                    '--list[List workflows]' \\
                    '--json[Output as JSON]' \\
                    '--help[Show help]'
                ;;
            completion)
                _arguments "1:(bash zsh fish)"
                ;;
        esac
    }

    # Hook into mix completion
    compdef _portfolio 'mix portfolio.*'
    """

    IO.puts(script)
  end

  defp generate_fish do
    script = """
    # Portfolio Manager Fish Completion
    # Save to ~/.config/fish/completions/portfolio.fish

    # Commands
    set -l portfolio_commands init scan add remove list show edit search sync status ask run config completion repl

    # Completions for mix portfolio.*
    complete -c mix -n "__fish_seen_subcommand_from portfolio.init" -s h -l help -d "Show help"
    complete -c mix -n "__fish_seen_subcommand_from portfolio.scan" -s h -l help -d "Show help"

    complete -c mix -n "__fish_seen_subcommand_from portfolio.list" -s s -l status -d "Filter by status" -xa "#{Enum.join(@statuses, " ")}"
    complete -c mix -n "__fish_seen_subcommand_from portfolio.list" -s t -l type -d "Filter by type" -xa "#{Enum.join(@types, " ")}"
    complete -c mix -n "__fish_seen_subcommand_from portfolio.list" -s l -l language -d "Filter by language" -xa "#{Enum.join(@languages, " ")}"
    complete -c mix -n "__fish_seen_subcommand_from portfolio.list" -l json -d "Output as JSON"
    complete -c mix -n "__fish_seen_subcommand_from portfolio.list" -s h -l help -d "Show help"

    complete -c mix -n "__fish_seen_subcommand_from portfolio.edit" -s t -l type -d "Set type" -xa "#{Enum.join(@types, " ")}"
    complete -c mix -n "__fish_seen_subcommand_from portfolio.edit" -s s -l status -d "Set status" -xa "#{Enum.join(@statuses, " ")}"
    complete -c mix -n "__fish_seen_subcommand_from portfolio.edit" -s p -l purpose -d "Set purpose"
    complete -c mix -n "__fish_seen_subcommand_from portfolio.edit" -l tags -d "Set tags"
    complete -c mix -n "__fish_seen_subcommand_from portfolio.edit" -l priority -d "Set priority" -xa "high medium low"
    complete -c mix -n "__fish_seen_subcommand_from portfolio.edit" -l note -d "Add a note"
    complete -c mix -n "__fish_seen_subcommand_from portfolio.edit" -l decision -d "Add a decision"
    complete -c mix -n "__fish_seen_subcommand_from portfolio.edit" -l json -d "Output as JSON"
    complete -c mix -n "__fish_seen_subcommand_from portfolio.edit" -s h -l help -d "Show help"

    complete -c mix -n "__fish_seen_subcommand_from portfolio.run" -s r -l repo -d "Target repository"
    complete -c mix -n "__fish_seen_subcommand_from portfolio.run" -l dry-run -d "Dry run mode"
    complete -c mix -n "__fish_seen_subcommand_from portfolio.run" -s v -l verbose -d "Verbose output"
    complete -c mix -n "__fish_seen_subcommand_from portfolio.run" -l list -d "List workflows"
    complete -c mix -n "__fish_seen_subcommand_from portfolio.run" -l json -d "Output as JSON"
    complete -c mix -n "__fish_seen_subcommand_from portfolio.run" -s h -l help -d "Show help"
    complete -c mix -n "__fish_seen_subcommand_from portfolio.run" -xa "port-check port-sync health-check doc-generate initial-setup"

    complete -c mix -n "__fish_seen_subcommand_from portfolio.sync" -l all -d "Refresh all repos"
    complete -c mix -n "__fish_seen_subcommand_from portfolio.sync" -l views -d "Regenerate views"
    complete -c mix -n "__fish_seen_subcommand_from portfolio.sync" -l json -d "Output as JSON"
    complete -c mix -n "__fish_seen_subcommand_from portfolio.sync" -s h -l help -d "Show help"

    complete -c mix -n "__fish_seen_subcommand_from portfolio.config" -xa "show get set list-dirs add-dir remove-dir"
    complete -c mix -n "__fish_seen_subcommand_from portfolio.config" -l json -d "Output as JSON"
    complete -c mix -n "__fish_seen_subcommand_from portfolio.config" -s h -l help -d "Show help"

    complete -c mix -n "__fish_seen_subcommand_from portfolio.completion" -xa "bash zsh fish"

    # Main portfolio commands
    complete -c mix -n "not __fish_seen_subcommand_from $portfolio_commands" -a "portfolio.init" -d "Initialize portfolio"
    complete -c mix -n "not __fish_seen_subcommand_from $portfolio_commands" -a "portfolio.scan" -d "Scan for repos"
    complete -c mix -n "not __fish_seen_subcommand_from $portfolio_commands" -a "portfolio.add" -d "Add a repo"
    complete -c mix -n "not __fish_seen_subcommand_from $portfolio_commands" -a "portfolio.remove" -d "Remove a repo"
    complete -c mix -n "not __fish_seen_subcommand_from $portfolio_commands" -a "portfolio.list" -d "List repos"
    complete -c mix -n "not __fish_seen_subcommand_from $portfolio_commands" -a "portfolio.show" -d "Show repo details"
    complete -c mix -n "not __fish_seen_subcommand_from $portfolio_commands" -a "portfolio.edit" -d "Edit repo"
    complete -c mix -n "not __fish_seen_subcommand_from $portfolio_commands" -a "portfolio.search" -d "Search repos"
    complete -c mix -n "not __fish_seen_subcommand_from $portfolio_commands" -a "portfolio.sync" -d "Sync portfolio"
    complete -c mix -n "not __fish_seen_subcommand_from $portfolio_commands" -a "portfolio.status" -d "Portfolio status"
    complete -c mix -n "not __fish_seen_subcommand_from $portfolio_commands" -a "portfolio.ask" -d "Ask questions"
    complete -c mix -n "not __fish_seen_subcommand_from $portfolio_commands" -a "portfolio.run" -d "Run workflow"
    complete -c mix -n "not __fish_seen_subcommand_from $portfolio_commands" -a "portfolio.config" -d "Manage config"
    complete -c mix -n "not __fish_seen_subcommand_from $portfolio_commands" -a "portfolio.completion" -d "Shell completions"
    complete -c mix -n "not __fish_seen_subcommand_from $portfolio_commands" -a "portfolio.repl" -d "Interactive mode"
    """

    IO.puts(script)
  end

  defp show_help do
    Mix.shell().info("""
    Usage: mix portfolio.completion <shell>

    Generate shell completion scripts.

    Supported shells:
      bash    Bash completion
      zsh     Zsh completion
      fish    Fish shell completion

    Examples:
      mix portfolio.completion bash > ~/.portfolio_completion.bash
      mix portfolio.completion zsh > ~/.portfolio_completion.zsh
      mix portfolio.completion fish > ~/.config/fish/completions/portfolio.fish
    """)
  end
end
