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

  alias PortfolioManager.CLI.Exit

  @commands ~w(init scan add remove list show edit search sync status ask run config graph review completion repl)
  @statuses ~w(active maintenance stale blocked archived)
  @types ~w(library application service port fork experiment template config docs monorepo archive)
  @languages ~w(elixir python javascript rust go ruby java cpp)

  @impl Mix.Task
  def run(args) do
    case args do
      ["bash"] ->
        generate_bash()

      ["zsh"] ->
        generate_zsh()

      ["fish"] ->
        generate_fish()

      ["--help"] ->
        show_help()

      [] ->
        show_help()

      _ ->
        show_help()
        Exit.halt(:invalid_args)
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
                add)
                    case "$prev" in
                        --type)
                            COMPREPLY=( $(compgen -W "$types" -- "$cur") )
                            return 0
                            ;;
                        --status)
                            COMPREPLY=( $(compgen -W "$statuses" -- "$cur") )
                            return 0
                            ;;
                    esac
                    COMPREPLY=( $(compgen -W "--id --type --status --detect --no-detect --json --help" -- "$cur") )
                    ;;
                remove)
                    COMPREPLY=( $(compgen -W "--force --keep-docs --json --help" -- "$cur") )
                    ;;
                scan)
                    COMPREPLY=( $(compgen -W "--dry-run --detect --no-detect --agentic --no-agentic --review --json --help" -- "$cur") )
                    ;;
                show)
                    case "$prev" in
                        --section)
                            COMPREPLY=( $(compgen -W "context notes decisions todos port" -- "$cur") )
                            return 0
                            ;;
                    esac
                    COMPREPLY=( $(compgen -W "--section --related --json --help" -- "$cur") )
                    ;;
                status)
                    COMPREPLY=( $(compgen -W "--json --help" -- "$cur") )
                    ;;
                ask)
                    COMPREPLY=( $(compgen -W "--provider --json --help" -- "$cur") )
                    ;;
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
                        --sort)
                            COMPREPLY=( $(compgen -W "name id last_commit commit_count_30d" -- "$cur") )
                            return 0
                            ;;
                        --format)
                            COMPREPLY=( $(compgen -W "table compact json" -- "$cur") )
                            return 0
                            ;;
                    esac
                    COMPREPLY=( $(compgen -W "--status --type --language --tag --sort --limit --format --json --help" -- "$cur") )
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
                    COMPREPLY=( $(compgen -W "--set --editor --type --status --purpose --tags --priority --note --decision --json --help" -- "$cur") )
                    ;;
                search)
                    COMPREPLY=( $(compgen -W "--field --regex --case-sensitive --json --help" -- "$cur") )
                    ;;
                run)
                    if [[ "$prev" == "run" || "$prev" == "portfolio.run" ]]; then
                        COMPREPLY=( $(compgen -W "port-check port-sync health-check doc-generate initial-setup --list" -- "$cur") )
                    else
                        COMPREPLY=( $(compgen -W "--repo --dry-run --verbose --list --json --help" -- "$cur") )
                    fi
                    ;;
                graph)
                    COMPREPLY=( $(compgen -W "--depth --type --output --ascii --json --help" -- "$cur") )
                    ;;
                review)
                    COMPREPLY=( $(compgen -W "--accept-all --threshold --json --help" -- "$cur") )
                    ;;
                sync)
                    COMPREPLY=( $(compgen -W "--full --computed-only --check-remotes --all --views --json --help" -- "$cur") )
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
            'graph:Show relationship graph'
            'review:Review pending detections'
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
            add)
                _arguments \\
                    '--id[Override repo id]' \\
                    '--type[Set type]:type:_portfolio_types' \\
                    '--status[Set status]:status:_portfolio_statuses' \\
                    '--detect[Run detection]' \\
                    '--no-detect[Skip detection]' \\
                    '--json[Output as JSON]' \\
                    '--help[Show help]'
                ;;
            remove)
                _arguments \\
                    '--force[Skip confirmation]' \\
                    '--keep-docs[Keep documents]' \\
                    '--json[Output as JSON]' \\
                    '--help[Show help]'
                ;;
            scan)
                _arguments \\
                    '--dry-run[Dry run]' \\
                    '--detect[Run detection]' \\
                    '--no-detect[Skip detection]' \\
                    '--agentic[Run agentic detection]' \\
                    '--no-agentic[Skip agentic detection]' \\
                    '--review[Review detections]' \\
                    '--json[Output as JSON]' \\
                    '--help[Show help]'
                ;;
            show)
                _arguments \\
                    '--section[Section]:(context notes decisions todos port)' \\
                    '--related[Include related repos]' \\
                    '--json[Output as JSON]' \\
                    '--help[Show help]'
                ;;
            status)
                _arguments \\
                    '--json[Output as JSON]' \\
                    '--help[Show help]'
                ;;
            ask)
                _arguments \\
                    '--provider[LLM provider]' \\
                    '--json[Output as JSON]' \\
                    '--help[Show help]'
                ;;
            list)
                _arguments \\
                    '--status[Filter by status]:status:_portfolio_statuses' \\
                    '--type[Filter by type]:type:_portfolio_types' \\
                    '--language[Filter by language]' \\
                    '--tag[Filter by tag]' \\
                    '--sort[Sort field]:(name id last_commit commit_count_30d)' \\
                    '--limit[Limit results]' \\
                    '--format[Output format]:(table compact json)' \\
                    '--json[Output as JSON]' \\
                    '--help[Show help]'
                ;;
            edit)
                _arguments \\
                    '--set[Set a field]' \\
                    '--editor[Editor]' \\
                    '--type[Set type]:type:_portfolio_types' \\
                    '--status[Set status]:status:_portfolio_statuses' \\
                    '--purpose[Set purpose]' \\
                    '--tags[Set tags]' \\
                    '--priority[Set priority]:(high medium low)' \\
                    '--json[Output as JSON]' \\
                    '--help[Show help]'
                ;;
            search)
                _arguments \\
                    '--field[Search fields]' \\
                    '--regex[Treat query as regex]' \\
                    '--case-sensitive[Case sensitive]' \\
                    '--json[Output as JSON]' \\
                    '--help[Show help]'
                ;;
            sync)
                _arguments \\
                    '--full[Full rescan]' \\
                    '--computed-only[Computed fields only]' \\
                    '--check-remotes[Fetch remotes]' \\
                    '--all[Legacy refresh all]' \\
                    '--views[Regenerate views]' \\
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
            graph)
                _arguments \\
                    '--depth[Graph depth]' \\
                    '--type[Filter relationship types]' \\
                    '--output[Output file]' \\
                    '--ascii[ASCII output]' \\
                    '--json[Output as JSON]' \\
                    '--help[Show help]'
                ;;
            review)
                _arguments \\
                    '--accept-all[Accept all above threshold]' \\
                    '--threshold[Confidence threshold]' \\
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
    set -l portfolio_commands init scan add remove list show edit search sync status ask run config graph review completion repl

    # Completions for mix portfolio.*
    complete -c mix -n "__fish_seen_subcommand_from portfolio.init" -s h -l help -d "Show help"
    complete -c mix -n "__fish_seen_subcommand_from portfolio.scan" -s h -l help -d "Show help"

    complete -c mix -n "__fish_seen_subcommand_from portfolio.list" -s s -l status -d "Filter by status" -xa "#{Enum.join(@statuses, " ")}"
    complete -c mix -n "__fish_seen_subcommand_from portfolio.list" -s t -l type -d "Filter by type" -xa "#{Enum.join(@types, " ")}"
    complete -c mix -n "__fish_seen_subcommand_from portfolio.list" -s l -l language -d "Filter by language" -xa "#{Enum.join(@languages, " ")}"
    complete -c mix -n "__fish_seen_subcommand_from portfolio.list" -l tag -d "Filter by tag"
    complete -c mix -n "__fish_seen_subcommand_from portfolio.list" -l sort -d "Sort by field" -xa "name id last_commit commit_count_30d"
    complete -c mix -n "__fish_seen_subcommand_from portfolio.list" -s n -l limit -d "Limit results"
    complete -c mix -n "__fish_seen_subcommand_from portfolio.list" -l format -d "Output format" -xa "table compact json"
    complete -c mix -n "__fish_seen_subcommand_from portfolio.list" -l json -d "Output as JSON"
    complete -c mix -n "__fish_seen_subcommand_from portfolio.list" -s h -l help -d "Show help"

    complete -c mix -n "__fish_seen_subcommand_from portfolio.add" -l id -d "Override repo id"
    complete -c mix -n "__fish_seen_subcommand_from portfolio.add" -l type -d "Set type" -xa "#{Enum.join(@types, " ")}"
    complete -c mix -n "__fish_seen_subcommand_from portfolio.add" -l status -d "Set status" -xa "#{Enum.join(@statuses, " ")}"
    complete -c mix -n "__fish_seen_subcommand_from portfolio.add" -l detect -d "Run detection"
    complete -c mix -n "__fish_seen_subcommand_from portfolio.add" -l no-detect -d "Skip detection"
    complete -c mix -n "__fish_seen_subcommand_from portfolio.add" -l json -d "Output as JSON"
    complete -c mix -n "__fish_seen_subcommand_from portfolio.add" -s h -l help -d "Show help"

    complete -c mix -n "__fish_seen_subcommand_from portfolio.remove" -s f -l force -d "Skip confirmation"
    complete -c mix -n "__fish_seen_subcommand_from portfolio.remove" -l keep-docs -d "Keep documents"
    complete -c mix -n "__fish_seen_subcommand_from portfolio.remove" -l json -d "Output as JSON"
    complete -c mix -n "__fish_seen_subcommand_from portfolio.remove" -s h -l help -d "Show help"

    complete -c mix -n "__fish_seen_subcommand_from portfolio.scan" -l dry-run -d "Dry run mode"
    complete -c mix -n "__fish_seen_subcommand_from portfolio.scan" -l detect -d "Run detection"
    complete -c mix -n "__fish_seen_subcommand_from portfolio.scan" -l no-detect -d "Skip detection"
    complete -c mix -n "__fish_seen_subcommand_from portfolio.scan" -l agentic -d "Run agentic detection"
    complete -c mix -n "__fish_seen_subcommand_from portfolio.scan" -l no-agentic -d "Skip agentic detection"
    complete -c mix -n "__fish_seen_subcommand_from portfolio.scan" -l review -d "Review detections"
    complete -c mix -n "__fish_seen_subcommand_from portfolio.scan" -l json -d "Output as JSON"
    complete -c mix -n "__fish_seen_subcommand_from portfolio.scan" -s h -l help -d "Show help"

    complete -c mix -n "__fish_seen_subcommand_from portfolio.show" -l section -d "Section" -xa "context notes decisions todos port"
    complete -c mix -n "__fish_seen_subcommand_from portfolio.show" -l related -d "Include related repos"
    complete -c mix -n "__fish_seen_subcommand_from portfolio.show" -l json -d "Output as JSON"
    complete -c mix -n "__fish_seen_subcommand_from portfolio.show" -s h -l help -d "Show help"

    complete -c mix -n "__fish_seen_subcommand_from portfolio.status" -l json -d "Output as JSON"
    complete -c mix -n "__fish_seen_subcommand_from portfolio.status" -s h -l help -d "Show help"

    complete -c mix -n "__fish_seen_subcommand_from portfolio.ask" -l provider -d "LLM provider"
    complete -c mix -n "__fish_seen_subcommand_from portfolio.ask" -l json -d "Output as JSON"
    complete -c mix -n "__fish_seen_subcommand_from portfolio.ask" -s h -l help -d "Show help"

    complete -c mix -n "__fish_seen_subcommand_from portfolio.edit" -s t -l type -d "Set type" -xa "#{Enum.join(@types, " ")}"
    complete -c mix -n "__fish_seen_subcommand_from portfolio.edit" -s s -l status -d "Set status" -xa "#{Enum.join(@statuses, " ")}"
    complete -c mix -n "__fish_seen_subcommand_from portfolio.edit" -s p -l purpose -d "Set purpose"
    complete -c mix -n "__fish_seen_subcommand_from portfolio.edit" -l tags -d "Set tags"
    complete -c mix -n "__fish_seen_subcommand_from portfolio.edit" -l priority -d "Set priority" -xa "high medium low"
    complete -c mix -n "__fish_seen_subcommand_from portfolio.edit" -l note -d "Add a note"
    complete -c mix -n "__fish_seen_subcommand_from portfolio.edit" -l decision -d "Add a decision"
    complete -c mix -n "__fish_seen_subcommand_from portfolio.edit" -l set -d "Set field"
    complete -c mix -n "__fish_seen_subcommand_from portfolio.edit" -l editor -d "Editor"
    complete -c mix -n "__fish_seen_subcommand_from portfolio.edit" -l json -d "Output as JSON"
    complete -c mix -n "__fish_seen_subcommand_from portfolio.edit" -s h -l help -d "Show help"

    complete -c mix -n "__fish_seen_subcommand_from portfolio.search" -s f -l field -d "Search fields"
    complete -c mix -n "__fish_seen_subcommand_from portfolio.search" -s r -l regex -d "Regex search"
    complete -c mix -n "__fish_seen_subcommand_from portfolio.search" -l case-sensitive -d "Case sensitive search"
    complete -c mix -n "__fish_seen_subcommand_from portfolio.search" -l json -d "Output as JSON"
    complete -c mix -n "__fish_seen_subcommand_from portfolio.search" -s h -l help -d "Show help"

    complete -c mix -n "__fish_seen_subcommand_from portfolio.run" -s r -l repo -d "Target repository"
    complete -c mix -n "__fish_seen_subcommand_from portfolio.run" -l dry-run -d "Dry run mode"
    complete -c mix -n "__fish_seen_subcommand_from portfolio.run" -s v -l verbose -d "Verbose output"
    complete -c mix -n "__fish_seen_subcommand_from portfolio.run" -l list -d "List workflows"
    complete -c mix -n "__fish_seen_subcommand_from portfolio.run" -l json -d "Output as JSON"
    complete -c mix -n "__fish_seen_subcommand_from portfolio.run" -s h -l help -d "Show help"
    complete -c mix -n "__fish_seen_subcommand_from portfolio.run" -xa "port-check port-sync health-check doc-generate initial-setup"

    complete -c mix -n "__fish_seen_subcommand_from portfolio.graph" -l depth -d "Graph depth"
    complete -c mix -n "__fish_seen_subcommand_from portfolio.graph" -l type -d "Filter relationship types"
    complete -c mix -n "__fish_seen_subcommand_from portfolio.graph" -s o -l output -d "Output file"
    complete -c mix -n "__fish_seen_subcommand_from portfolio.graph" -l ascii -d "ASCII output"
    complete -c mix -n "__fish_seen_subcommand_from portfolio.graph" -l json -d "Output as JSON"
    complete -c mix -n "__fish_seen_subcommand_from portfolio.graph" -s h -l help -d "Show help"

    complete -c mix -n "__fish_seen_subcommand_from portfolio.review" -l accept-all -d "Accept all above threshold"
    complete -c mix -n "__fish_seen_subcommand_from portfolio.review" -l threshold -d "Confidence threshold"
    complete -c mix -n "__fish_seen_subcommand_from portfolio.review" -l json -d "Output as JSON"
    complete -c mix -n "__fish_seen_subcommand_from portfolio.review" -s h -l help -d "Show help"

    complete -c mix -n "__fish_seen_subcommand_from portfolio.sync" -l full -d "Full rescan"
    complete -c mix -n "__fish_seen_subcommand_from portfolio.sync" -l computed-only -d "Computed fields only"
    complete -c mix -n "__fish_seen_subcommand_from portfolio.sync" -l check-remotes -d "Fetch remotes"
    complete -c mix -n "__fish_seen_subcommand_from portfolio.sync" -l all -d "Legacy refresh all"
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
    complete -c mix -n "not __fish_seen_subcommand_from $portfolio_commands" -a "portfolio.graph" -d "Show graph"
    complete -c mix -n "not __fish_seen_subcommand_from $portfolio_commands" -a "portfolio.review" -d "Review detections"
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
