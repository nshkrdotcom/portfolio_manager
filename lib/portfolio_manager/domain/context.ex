defmodule PortfolioManager.Domain.Context do
  @moduledoc """
  Domain entity representing the full context for a repository.

  Context includes the repo metadata plus notes, decisions, and computed data.
  """

  alias PortfolioManager.Domain.{Relationship, Repo}

  @type decision :: %{
          id: String.t(),
          title: String.t(),
          content: String.t(),
          date: Date.t() | nil
        }

  @type t :: %__MODULE__{
          repo: Repo.t(),
          notes: String.t() | nil,
          decisions: [decision()],
          relationships: [Relationship.t()],
          todos: [String.t()],
          computed: map()
        }

  defstruct [
    :repo,
    notes: nil,
    decisions: [],
    relationships: [],
    todos: [],
    computed: %{}
  ]

  @doc """
  Creates a new Context struct from a repo.
  """
  @spec new(Repo.t()) :: t()
  def new(%Repo{} = repo) do
    %__MODULE__{repo: repo}
  end

  @doc """
  Creates a new Context from raw attributes.
  """
  @spec from_map(map()) :: {:ok, t()} | {:error, term()}
  def from_map(attrs) when is_map(attrs) do
    with {:ok, repo} <- Repo.new(get_attr(attrs, :repo) || attrs) do
      context = %__MODULE__{
        repo: repo,
        notes: get_attr(attrs, :notes),
        decisions: normalize_decisions(get_attr(attrs, :decisions) || []),
        todos: get_attr(attrs, :todos) || [],
        computed: get_attr(attrs, :computed) || %{}
      }

      {:ok, context}
    end
  end

  @doc """
  Updates the context with new attributes.
  """
  @spec update(t(), map()) :: {:ok, t()} | {:error, term()}
  def update(%__MODULE__{} = context, attrs) when is_map(attrs) do
    with {:ok, updated_repo} <- maybe_update_repo(context.repo, attrs) do
      updated =
        context
        |> Map.put(:repo, updated_repo)
        |> maybe_update_field(:notes, attrs)
        |> maybe_update_field(:todos, attrs)
        |> maybe_update_field(:computed, attrs)

      {:ok, updated}
    end
  end

  @doc """
  Adds a note to the context.
  """
  @spec add_note(t(), String.t()) :: t()
  def add_note(%__MODULE__{} = context, content) when is_binary(content) do
    timestamp = DateTime.utc_now() |> DateTime.to_iso8601()
    new_note = "\n\n## Note (#{timestamp})\n\n#{content}"

    updated_notes =
      case context.notes do
        nil -> content
        existing -> existing <> new_note
      end

    %{context | notes: updated_notes}
  end

  @doc """
  Adds a decision to the context.
  """
  @spec add_decision(t(), String.t(), String.t()) :: t()
  def add_decision(%__MODULE__{} = context, title, content) do
    decision = %{
      id: generate_decision_id(context.decisions),
      title: title,
      content: content,
      date: Date.utc_today()
    }

    %{context | decisions: context.decisions ++ [decision]}
  end

  @doc """
  Adds a todo item.
  """
  @spec add_todo(t(), String.t()) :: t()
  def add_todo(%__MODULE__{} = context, todo) when is_binary(todo) do
    %{context | todos: context.todos ++ [todo]}
  end

  @doc """
  Removes a todo item.
  """
  @spec remove_todo(t(), String.t()) :: t()
  def remove_todo(%__MODULE__{} = context, todo) when is_binary(todo) do
    %{context | todos: Enum.reject(context.todos, &(&1 == todo))}
  end

  @doc """
  Adds computed data to the context.
  """
  @spec set_computed(t(), atom() | String.t(), term()) :: t()
  def set_computed(%__MODULE__{} = context, key, value) do
    key = if is_atom(key), do: to_string(key), else: key
    %{context | computed: Map.put(context.computed, key, value)}
  end

  @doc """
  Converts context to a map for serialization.
  """
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = context) do
    base = Repo.to_map(context.repo)

    base
    |> Map.put("notes", context.notes)
    |> Map.put("decisions", Enum.map(context.decisions, &decision_to_map/1))
    |> Map.put("todos", context.todos)
    |> Map.put("computed", context.computed)
    |> Enum.reject(fn {_k, v} -> is_nil(v) or v == [] or v == %{} end)
    |> Map.new()
  end

  # Private helpers

  defp get_attr(map, key) do
    Map.get(map, key) || Map.get(map, to_string(key))
  end

  defp normalize_decisions(decisions) when is_list(decisions) do
    Enum.map(decisions, fn d ->
      %{
        id: Map.get(d, :id) || Map.get(d, "id"),
        title: Map.get(d, :title) || Map.get(d, "title"),
        content: Map.get(d, :content) || Map.get(d, "content"),
        date: parse_date(Map.get(d, :date) || Map.get(d, "date"))
      }
    end)
  end

  defp parse_date(nil), do: nil
  defp parse_date(%Date{} = d), do: d
  defp parse_date(s) when is_binary(s), do: Date.from_iso8601!(s)

  defp decision_to_map(decision) do
    %{
      "id" => decision.id,
      "title" => decision.title,
      "content" => decision.content,
      "date" => decision.date && Date.to_iso8601(decision.date)
    }
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Map.new()
  end

  defp generate_decision_id(decisions) do
    next_num = length(decisions) + 1
    String.pad_leading(to_string(next_num), 3, "0")
  end

  defp maybe_update_repo(repo, attrs) do
    repo_updates = Map.get(attrs, :repo) || Map.get(attrs, "repo") || %{}

    # Also check for top-level repo fields
    top_level_repo_fields = [
      :type,
      :status,
      :language,
      :framework,
      :purpose,
      :tags,
      :priority,
      :port
    ]

    all_updates =
      Enum.reduce(top_level_repo_fields, repo_updates, fn field, acc ->
        str_field = to_string(field)

        cond do
          Map.has_key?(attrs, field) -> Map.put(acc, field, Map.get(attrs, field))
          Map.has_key?(attrs, str_field) -> Map.put(acc, str_field, Map.get(attrs, str_field))
          true -> acc
        end
      end)

    if map_size(all_updates) > 0 do
      Repo.update(repo, all_updates)
    else
      {:ok, repo}
    end
  end

  defp maybe_update_field(context, field, attrs) do
    str_field = to_string(field)

    value =
      cond do
        Map.has_key?(attrs, field) -> Map.get(attrs, field)
        Map.has_key?(attrs, str_field) -> Map.get(attrs, str_field)
        true -> nil
      end

    if value do
      Map.put(context, field, value)
    else
      context
    end
  end
end
