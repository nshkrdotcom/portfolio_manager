defmodule PortfolioManager.Portfolio do
  @moduledoc """
  GenServer managing a portfolio instance.

  This is the stateful component that holds the loaded registry
  and provides operations on it.
  """

  use GenServer

  alias PortfolioManager.Domain.{Context, Registry, Repo, Relationship}
  alias PortfolioManager.Ports.{Storage, Git, Detection}

  @type t :: %__MODULE__{
          path: String.t(),
          registry: Registry.t(),
          storage: term(),
          config: map()
        }

  defstruct [:path, :registry, :storage, :config]

  # Client API

  @doc """
  Starts a portfolio process.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    name = Keyword.get(opts, :name)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Gets the current state of the portfolio.
  """
  @spec get_state(GenServer.server()) :: t()
  def get_state(server) do
    GenServer.call(server, :get_state)
  end

  @doc """
  Lists all repos in the portfolio.
  """
  @spec list_repos(GenServer.server(), keyword()) :: [Repo.t()]
  def list_repos(server, opts \\ []) do
    GenServer.call(server, {:list_repos, opts})
  end

  @doc """
  Gets a repo by ID.
  """
  @spec get_repo(GenServer.server(), String.t()) :: {:ok, Repo.t()} | {:error, :not_found}
  def get_repo(server, repo_id) do
    GenServer.call(server, {:get_repo, repo_id})
  end

  @doc """
  Gets context for a repo.
  """
  @spec get_context(GenServer.server(), String.t()) :: {:ok, Context.t()} | {:error, term()}
  def get_context(server, repo_id) do
    GenServer.call(server, {:get_context, repo_id})
  end

  @doc """
  Adds a repo to the portfolio.
  """
  @spec add_repo(GenServer.server(), String.t()) :: {:ok, Repo.t()} | {:error, term()}
  def add_repo(server, path) do
    GenServer.call(server, {:add_repo, path})
  end

  @doc """
  Removes a repo from the portfolio.
  """
  @spec remove_repo(GenServer.server(), String.t()) :: :ok | {:error, term()}
  def remove_repo(server, repo_id) do
    GenServer.call(server, {:remove_repo, repo_id})
  end

  @doc """
  Updates a repo's context.
  """
  @spec update_context(GenServer.server(), String.t(), map()) ::
          {:ok, Context.t()} | {:error, term()}
  def update_context(server, repo_id, updates) do
    GenServer.call(server, {:update_context, repo_id, updates})
  end

  @doc """
  Adds a relationship between repos.
  """
  @spec add_relationship(GenServer.server(), String.t(), String.t(), atom()) ::
          {:ok, Relationship.t()} | {:error, term()}
  def add_relationship(server, from, to, type) do
    GenServer.call(server, {:add_relationship, from, to, type})
  end

  @doc """
  Gets relationships for a repo.
  """
  @spec get_relationships(GenServer.server(), String.t()) :: [Relationship.t()]
  def get_relationships(server, repo_id) do
    GenServer.call(server, {:get_relationships, repo_id})
  end

  @doc """
  Searches repos.
  """
  @spec search(GenServer.server(), String.t(), keyword()) :: [Repo.t()]
  def search(server, query, opts \\ []) do
    GenServer.call(server, {:search, query, opts})
  end

  @doc """
  Scans directories for repos.
  """
  @spec scan(GenServer.server(), [String.t()]) :: {:ok, [Repo.t()]} | {:error, term()}
  def scan(server, directories) do
    GenServer.call(server, {:scan, directories}, :infinity)
  end

  @doc """
  Saves the current state to storage.
  """
  @spec save(GenServer.server()) :: :ok | {:error, term()}
  def save(server) do
    GenServer.call(server, :save)
  end

  @doc """
  Returns portfolio statistics.
  """
  @spec stats(GenServer.server()) :: map()
  def stats(server) do
    GenServer.call(server, :stats)
  end

  # Server callbacks

  @impl true
  def init(opts) do
    path = Keyword.fetch!(opts, :path)
    storage_adapter = Keyword.get(opts, :storage_adapter, Storage.adapter())

    case storage_adapter.init(path) do
      {:ok, storage_state} ->
        case storage_adapter.load_registry(storage_state) do
          {:ok, registry} ->
            state = %__MODULE__{
              path: path,
              registry: registry,
              storage: {storage_adapter, storage_state},
              config: %{}
            }

            {:ok, state}

          {:error, reason} ->
            {:stop, reason}
        end

      {:error, reason} ->
        {:stop, reason}
    end
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    {:reply, state, state}
  end

  def handle_call({:list_repos, opts}, _from, state) do
    repos = Registry.list_repos(state.registry, opts)
    {:reply, repos, state}
  end

  def handle_call({:get_repo, repo_id}, _from, state) do
    result = Registry.get_repo(state.registry, repo_id)
    {:reply, result, state}
  end

  def handle_call({:get_context, repo_id}, _from, state) do
    {adapter, storage_state} = state.storage

    case Registry.get_repo(state.registry, repo_id) do
      {:ok, _repo} ->
        result = adapter.load_context(storage_state, repo_id)
        {:reply, result, state}

      {:error, _} = error ->
        {:reply, error, state}
    end
  end

  def handle_call({:add_repo, path}, _from, state) do
    expanded = Path.expand(path)
    git_adapter = Git.adapter()
    detection_adapter = Detection.adapter()

    with true <- git_adapter.is_repo?(expanded),
         {:ok, git_info} <- git_adapter.get_info(expanded),
         {:ok, detection} <- detection_adapter.detect(expanded) do
      repo_id = Repo.generate_id(expanded)
      name = Path.basename(expanded)

      repo_attrs = %{
        id: repo_id,
        name: name,
        path: expanded,
        remote_url: git_info.remote_url,
        type: detection.type,
        status: :active,
        language: detection.language
      }

      case Repo.new(repo_attrs) do
        {:ok, repo} ->
          case Registry.add_repo(state.registry, repo) do
            {:ok, updated_registry} ->
              # Create initial context
              context = Context.new(repo)
              {adapter, storage_state} = state.storage
              :ok = adapter.save_context(storage_state, context)

              new_state = %{state | registry: updated_registry}
              {:reply, {:ok, repo}, new_state}

            {:error, _} = error ->
              {:reply, error, state}
          end

        {:error, _} = error ->
          {:reply, error, state}
      end
    else
      false -> {:reply, {:error, :not_a_repo}, state}
      {:error, _} = error -> {:reply, error, state}
    end
  end

  def handle_call({:remove_repo, repo_id}, _from, state) do
    case Registry.remove_repo(state.registry, repo_id) do
      {:ok, updated_registry} ->
        new_state = %{state | registry: updated_registry}
        {:reply, :ok, new_state}

      {:error, _} = error ->
        {:reply, error, state}
    end
  end

  def handle_call({:update_context, repo_id, updates}, _from, state) do
    {adapter, storage_state} = state.storage

    with {:ok, context} <- adapter.load_context(storage_state, repo_id),
         {:ok, updated_context} <- Context.update(context, updates),
         :ok <- adapter.save_context(storage_state, updated_context),
         {:ok, updated_registry} <- Registry.update_repo(state.registry, repo_id, updates) do
      new_state = %{state | registry: updated_registry}
      {:reply, {:ok, updated_context}, new_state}
    else
      {:error, _} = error -> {:reply, error, state}
    end
  end

  def handle_call({:add_relationship, from, to, type}, _from, state) do
    case Relationship.new(%{from: from, to: to, type: type}) do
      {:ok, rel} ->
        {:ok, updated_registry} = Registry.add_relationship(state.registry, rel)
        new_state = %{state | registry: updated_registry}
        {:reply, {:ok, rel}, new_state}

      {:error, _} = error ->
        {:reply, error, state}
    end
  end

  def handle_call({:get_relationships, repo_id}, _from, state) do
    rels = Registry.get_relationships(state.registry, repo_id)
    {:reply, rels, state}
  end

  def handle_call({:search, query, opts}, _from, state) do
    results = Registry.search(state.registry, query, opts)
    {:reply, results, state}
  end

  def handle_call({:scan, directories}, _from, state) do
    git_adapter = Git.adapter()

    discovered =
      directories
      |> Enum.flat_map(fn dir ->
        expanded = Path.expand(dir)
        git_adapter.discover_repos(expanded)
      end)
      |> Enum.uniq()

    # Add repos that aren't already tracked
    existing_paths =
      state.registry
      |> Registry.list_repos()
      |> Enum.map(& &1.path)
      |> MapSet.new()

    new_repos =
      discovered
      |> Enum.reject(&MapSet.member?(existing_paths, &1))
      |> Enum.map(fn path ->
        # Use same logic as add_repo but collect results
        detection_adapter = Detection.adapter()

        case detection_adapter.detect(path) do
          {:ok, detection} ->
            {:ok, git_info} = git_adapter.get_info(path)

            %{
              id: Repo.generate_id(path),
              name: Path.basename(path),
              path: path,
              remote_url: git_info.remote_url,
              type: detection.type,
              status: :active,
              language: detection.language
            }

          {:error, _} ->
            nil
        end
      end)
      |> Enum.reject(&is_nil/1)

    # Add all new repos to registry and create contexts
    {adapter, storage_state} = state.storage

    {updated_registry, added_repos} =
      Enum.reduce(new_repos, {state.registry, []}, fn attrs, {reg, acc} ->
        case Repo.new(attrs) do
          {:ok, repo} ->
            case Registry.add_repo(reg, repo) do
              {:ok, new_reg} ->
                # Create initial context for the repo
                context = Context.new(repo)
                _ = adapter.save_context(storage_state, context)
                {new_reg, [repo | acc]}

              {:error, _} ->
                {reg, acc}
            end

          {:error, _} ->
            {reg, acc}
        end
      end)

    new_state = %{state | registry: updated_registry}
    {:reply, {:ok, Enum.reverse(added_repos)}, new_state}
  end

  def handle_call(:save, _from, state) do
    {adapter, storage_state} = state.storage
    result = adapter.save_registry(storage_state, state.registry)
    {:reply, result, state}
  end

  def handle_call(:stats, _from, state) do
    stats = Registry.stats(state.registry)
    {:reply, stats, state}
  end
end
