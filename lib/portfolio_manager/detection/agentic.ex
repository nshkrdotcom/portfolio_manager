defmodule PortfolioManager.Detection.Agentic do
  @moduledoc """
  LLM-based detection for repository analysis.

  Uses AI to infer purpose, type, relationships, and status
  when deterministic detection is insufficient.
  """

  @doc """
  Detects the purpose of a repository from its content.

  Analyzes README, code structure, and other indicators.

  ## Options

    * `:provider` - LLM provider to use
    * `:portfolio` - Portfolio for context (optional)

  ## Returns

    * `{:ok, %{purpose: String.t(), confidence: float()}}`
    * `{:error, term()}`

  """
  @spec detect_purpose(String.t(), keyword()) ::
          {:ok, %{purpose: String.t(), confidence: float()}} | {:error, term()}
  def detect_purpose(repo_path, opts \\ []) do
    context = build_context(repo_path)

    prompt = """
    Analyze this repository and describe its purpose in 1-2 sentences.

    Repository information:
    #{context}

    Respond with ONLY a JSON object in this format:
    {"purpose": "Brief description of what this project does", "confidence": 0.8}

    The confidence should be between 0.0 and 1.0 based on how certain you are.
    """

    case query_llm(prompt, opts) do
      {:ok, response} -> parse_purpose_response(response)
      {:error, _} = error -> error
    end
  end

  @doc """
  Detects the type of a repository.

  ## Types

    * `:library` - Reusable library/package
    * `:application` - Standalone application
    * `:port` - Port of another project
    * `:fork` - Fork of another project
    * `:experiment` - Experimental/prototype
    * `:template` - Project template
    * `:config` - Configuration files
    * `:docs` - Documentation project

  """
  @spec detect_type(String.t(), keyword()) ::
          {:ok, %{type: atom(), confidence: float()}} | {:error, term()}
  def detect_type(repo_path, opts \\ []) do
    context = build_context(repo_path)

    prompt = """
    Classify this repository into one of these types:
    - library: Reusable library/package
    - application: Standalone application
    - port: Port/implementation of another project in a different language
    - fork: Fork of another project
    - experiment: Experimental/prototype code
    - template: Project template/boilerplate
    - config: Configuration files repository
    - docs: Documentation repository

    Repository information:
    #{context}

    Respond with ONLY a JSON object in this format:
    {"type": "library", "confidence": 0.9, "reasoning": "Brief explanation"}
    """

    case query_llm(prompt, opts) do
      {:ok, response} -> parse_type_response(response)
      {:error, _} = error -> error
    end
  end

  @doc """
  Detects relationships to other repositories.

  Finds dependencies, ports, forks, and related projects.
  """
  @spec detect_relationships(String.t(), GenServer.server(), keyword()) ::
          {:ok, [map()]} | {:error, term()}
  def detect_relationships(repo_path, portfolio, opts \\ []) do
    context = build_context(repo_path)

    # Get list of other repos for matching
    other_repos = PortfolioManager.list_repos(portfolio)

    repo_list =
      other_repos
      |> Enum.map(fn r -> "- #{r.id}: #{r.name} (#{r.type}, #{r.language})" end)
      |> Enum.join("\n")

    prompt = """
    Analyze this repository and find relationships to other projects.

    Current repository:
    #{context}

    Other repositories in portfolio:
    #{repo_list}

    Relationship types:
    - depends_on: Uses another repo as a dependency
    - port_of: Is a port/reimplementation of another project
    - fork_of: Is a fork of another project
    - evolved_from: Evolved from or inspired by another project
    - related_to: General relationship

    Respond with ONLY a JSON object in this format:
    {"relationships": [
      {"to": "repo-id", "type": "depends_on", "confidence": 0.9}
    ]}

    If no relationships found, return: {"relationships": []}
    """

    case query_llm(prompt, opts) do
      {:ok, response} -> parse_relationships_response(response)
      {:error, _} = error -> error
    end
  end

  @doc """
  Detects the status of a repository.

  ## Statuses

    * `:active` - Actively developed
    * `:maintenance` - In maintenance mode
    * `:stale` - No recent activity
    * `:blocked` - Blocked on something
    * `:archived` - No longer maintained

  """
  @spec detect_status(String.t(), keyword()) ::
          {:ok, %{status: atom(), confidence: float()}} | {:error, term()}
  def detect_status(repo_path, opts \\ []) do
    context = build_context(repo_path)

    # Get git activity
    activity = get_git_activity(repo_path)

    prompt = """
    Determine the development status of this repository.

    Repository information:
    #{context}

    Git activity:
    #{activity}

    Statuses:
    - active: Regularly updated, actively developed
    - maintenance: Stable, occasional updates for bugs/security
    - stale: No recent commits (30+ days)
    - blocked: Waiting on something (dependencies, decisions)
    - archived: No longer maintained

    Respond with ONLY a JSON object in this format:
    {"status": "active", "confidence": 0.85, "reasoning": "Brief explanation"}
    """

    case query_llm(prompt, opts) do
      {:ok, response} -> parse_status_response(response)
      {:error, _} = error -> error
    end
  end

  @doc """
  Performs full agentic analysis of a repository.

  Returns combined results from all detection methods.
  """
  @spec analyze(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def analyze(repo_path, opts \\ []) do
    results = %{}

    results =
      case detect_purpose(repo_path, opts) do
        {:ok, purpose} -> Map.put(results, :purpose, purpose)
        _ -> results
      end

    results =
      case detect_type(repo_path, opts) do
        {:ok, type} -> Map.put(results, :type, type)
        _ -> results
      end

    results =
      case detect_status(repo_path, opts) do
        {:ok, status} -> Map.put(results, :status, status)
        _ -> results
      end

    {:ok, results}
  end

  # Private helpers

  defp build_context(repo_path) do
    parts = []

    # Read README if exists
    readme = read_file(repo_path, ["README.md", "README.txt", "README"])

    parts =
      if readme do
        parts ++ ["README:\n#{String.slice(readme, 0, 2000)}"]
      else
        parts
      end

    # Detect language indicators
    files = list_root_files(repo_path)
    parts = parts ++ ["Root files: #{Enum.join(files, ", ")}"]

    # Get package/project name from manifest
    manifest = read_manifest(repo_path)
    parts = if manifest, do: parts ++ ["Manifest:\n#{manifest}"], else: parts

    Enum.join(parts, "\n\n")
  end

  defp read_file(base_path, filenames) when is_list(filenames) do
    filenames
    |> Enum.map(&Path.join(base_path, &1))
    |> Enum.find(&File.exists?/1)
    |> case do
      nil -> nil
      path -> File.read!(path)
    end
  end

  defp read_manifest(path) do
    manifests = [
      {"mix.exs", :elixir},
      {"package.json", :javascript},
      {"Cargo.toml", :rust},
      {"pyproject.toml", :python},
      {"go.mod", :go}
    ]

    Enum.find_value(manifests, fn {file, _lang} ->
      full_path = Path.join(path, file)

      if File.exists?(full_path) do
        content = File.read!(full_path)
        # Limit size
        String.slice(content, 0, 1000)
      end
    end)
  end

  defp list_root_files(path) do
    case File.ls(path) do
      {:ok, files} ->
        files
        |> Enum.filter(&(not String.starts_with?(&1, ".")))
        |> Enum.take(20)

      _ ->
        []
    end
  end

  defp get_git_activity(path) do
    parts = []

    # Last commit date
    parts =
      case run_git(path, ["log", "-1", "--format=%ci"]) do
        {:ok, date} -> parts ++ ["Last commit: #{String.trim(date)}"]
        _ -> parts
      end

    # Commits in last 30 days
    parts =
      case run_git(path, ["rev-list", "--count", "--since=30 days ago", "HEAD"]) do
        {:ok, count} -> parts ++ ["Commits (30 days): #{String.trim(count)}"]
        _ -> parts
      end

    # Total commits
    parts =
      case run_git(path, ["rev-list", "--count", "HEAD"]) do
        {:ok, count} -> parts ++ ["Total commits: #{String.trim(count)}"]
        _ -> parts
      end

    Enum.join(parts, "\n")
  end

  defp run_git(path, args) do
    case System.cmd("git", args, cd: path, stderr_to_stdout: true) do
      {output, 0} -> {:ok, output}
      {error, _} -> {:error, error}
    end
  end

  defp query_llm(prompt, _opts) do
    # Try to use Gemini directly if available
    case Code.ensure_loaded?(Rag.Ai.Gemini) do
      true ->
        provider = Rag.Ai.Gemini.new(%{})

        case Rag.Ai.Gemini.generate_text(provider, prompt, []) do
          {:ok, response} -> {:ok, response}
          {:error, _} = error -> error
        end

      false ->
        # Fallback: return error if RAG not available
        {:error, :rag_not_available}
    end
  end

  defp parse_purpose_response(response) do
    case extract_json(response) do
      {:ok, %{"purpose" => purpose, "confidence" => confidence}} ->
        {:ok, %{purpose: purpose, confidence: confidence}}

      {:ok, %{"purpose" => purpose}} ->
        {:ok, %{purpose: purpose, confidence: 0.7}}

      _ ->
        # Try to use the response as-is
        {:ok, %{purpose: response, confidence: 0.5}}
    end
  end

  @valid_types_list ~w(library application port fork experiment template config docs unknown)

  defp parse_type_response(response) do
    case extract_json(response) do
      {:ok, %{"type" => type, "confidence" => confidence}} ->
        if type in @valid_types_list do
          {:ok, %{type: String.to_atom(type), confidence: confidence}}
        else
          {:ok, %{type: :unknown, confidence: 0.3}}
        end

      {:ok, %{"type" => type}} ->
        if type in @valid_types_list do
          {:ok, %{type: String.to_atom(type), confidence: 0.7}}
        else
          {:ok, %{type: :unknown, confidence: 0.3}}
        end

      _ ->
        {:ok, %{type: :unknown, confidence: 0.3}}
    end
  end

  defp parse_relationships_response(response) do
    case extract_json(response) do
      {:ok, %{"relationships" => rels}} when is_list(rels) ->
        parsed =
          Enum.map(rels, fn rel ->
            %{
              to: Map.get(rel, "to"),
              type: String.to_atom(Map.get(rel, "type", "related_to")),
              confidence: Map.get(rel, "confidence", 0.7)
            }
          end)
          |> Enum.filter(&(&1.to != nil))

        {:ok, parsed}

      _ ->
        {:ok, []}
    end
  end

  @valid_statuses_list ~w(active maintenance stale blocked archived unknown)

  defp parse_status_response(response) do
    case extract_json(response) do
      {:ok, %{"status" => status, "confidence" => confidence}} ->
        if status in @valid_statuses_list do
          {:ok, %{status: String.to_atom(status), confidence: confidence}}
        else
          {:ok, %{status: :unknown, confidence: 0.3}}
        end

      {:ok, %{"status" => status}} ->
        if status in @valid_statuses_list do
          {:ok, %{status: String.to_atom(status), confidence: 0.7}}
        else
          {:ok, %{status: :unknown, confidence: 0.3}}
        end

      _ ->
        {:ok, %{status: :unknown, confidence: 0.3}}
    end
  end

  defp extract_json(text) do
    # Try to find JSON in the response
    case Regex.run(~r/\{[^{}]*\}/, text) do
      [json_str] ->
        case Jason.decode(json_str) do
          {:ok, data} -> {:ok, data}
          _ -> {:error, :invalid_json}
        end

      _ ->
        {:error, :no_json_found}
    end
  end
end
