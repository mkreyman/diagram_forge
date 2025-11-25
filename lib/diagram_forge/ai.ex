defmodule DiagramForge.AI do
  @moduledoc """
  The AI context - handles configurable AI prompts with caching.

  Prompts can be customized via the admin interface. When a prompt is not
  found in the database, the hardcoded default from `DiagramForge.AI.Prompts`
  is used instead.
  """

  alias DiagramForge.AI.Prompt
  alias DiagramForge.AI.Prompts
  alias DiagramForge.Repo

  # Cache table name
  @cache_table :prompt_cache

  @doc """
  Starts the ETS cache for prompts. Called from Application.start/2.
  """
  def start_cache do
    :ets.new(@cache_table, [:named_table, :public, read_concurrency: true])
  end

  @doc """
  Gets a prompt by key, checking cache first, then DB, then falling back to defaults.
  """
  def get_prompt(key) when is_atom(key), do: get_prompt(Atom.to_string(key))

  def get_prompt(key) when is_binary(key) do
    case :ets.lookup(@cache_table, key) do
      [{^key, content}] -> content
      [] -> fetch_and_cache(key)
    end
  end

  defp fetch_and_cache(key) do
    content =
      case Repo.get_by(Prompt, key: key) do
        %Prompt{content: content} -> content
        nil -> default_prompt(key)
      end

    :ets.insert(@cache_table, {key, content})
    content
  end

  @doc """
  Invalidates the cache for a specific prompt key.
  """
  def invalidate_cache(key) when is_binary(key) do
    :ets.delete(@cache_table, key)
  end

  def invalidate_cache(key) when is_atom(key) do
    invalidate_cache(Atom.to_string(key))
  end

  @doc """
  Invalidates all cached prompts.
  """
  def invalidate_all_cache do
    :ets.delete_all_objects(@cache_table)
  end

  # Default prompts (fallback) - calls the default functions to avoid circular deps
  defp default_prompt("concept_system"), do: Prompts.default_concept_system_prompt()
  defp default_prompt("diagram_system"), do: Prompts.default_diagram_system_prompt()
  defp default_prompt(_), do: nil

  # Known prompt keys with descriptions for admin UI
  @doc false
  def known_prompt_keys do
    [
      {"concept_system", "System prompt for concept extraction from documents"},
      {"diagram_system", "System prompt for diagram generation"}
    ]
  end

  # CRUD operations

  @doc """
  Lists all prompts from the database.
  """
  def list_prompts, do: Repo.all(Prompt)

  @doc """
  Gets a prompt by ID.
  """
  def get_prompt!(id), do: Repo.get!(Prompt, id)

  @doc """
  Creates a new prompt.
  """
  def create_prompt(attrs) do
    %Prompt{}
    |> Prompt.changeset(attrs)
    |> Repo.insert()
    |> tap_invalidate_cache()
  end

  @doc """
  Updates an existing prompt.
  """
  def update_prompt(%Prompt{} = prompt, attrs) do
    prompt
    |> Prompt.changeset(attrs)
    |> Repo.update()
    |> tap_invalidate_cache()
  end

  @doc """
  Deletes a prompt (resets to default).
  """
  def delete_prompt(%Prompt{} = prompt) do
    prompt
    |> Repo.delete()
    |> tap_invalidate_cache()
  end

  defp tap_invalidate_cache({:ok, %Prompt{key: key}} = result) do
    invalidate_cache(key)
    result
  end

  defp tap_invalidate_cache(error), do: error

  # Admin helper functions

  @doc """
  Lists all known prompts with their current status (default or customized).
  Used by the admin interface.
  """
  def list_all_prompts_with_status do
    db_prompts = Repo.all(Prompt) |> Map.new(&{&1.key, &1})

    for {key, description} <- known_prompt_keys() do
      build_prompt_status(key, description, Map.get(db_prompts, key))
    end
  end

  @doc """
  Gets a single prompt with its status by key.
  Used by the admin edit page.
  """
  def get_prompt_with_status(key) when is_binary(key) do
    {_key, description} =
      known_prompt_keys()
      |> Enum.find({key, nil}, fn {k, _desc} -> k == key end)

    db_prompt = Repo.get_by(Prompt, key: key)
    build_prompt_status(key, description, db_prompt)
  end

  defp build_prompt_status(key, description, nil) do
    %{
      key: key,
      description: description,
      content: default_prompt(key),
      source: :default,
      db_record: nil
    }
  end

  defp build_prompt_status(key, description, prompt) do
    %{
      key: key,
      description: description,
      content: prompt.content,
      source: :database,
      db_record: prompt
    }
  end
end
