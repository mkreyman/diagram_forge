# Configurable AI Prompts Implementation

## Overview

Make AI prompts editable via admin interface instead of hardcoded in the `DiagramForge.AI.Prompts` module. Current hardcoded prompts become defaults, with database-stored versions taking precedence.

## Database Design

### Table: `prompts`

| Column | Type | Constraints | Description |
|--------|------|-------------|-------------|
| id | binary_id | primary key | Auto-generated UUID |
| key | string | unique, not null | Identifier (e.g., "diagram_system") |
| content | text | not null | The actual prompt text |
| description | string | | Short description for admin UI display |
| inserted_at | utc_datetime | | |
| updated_at | utc_datetime | | |

### Prompt Keys

| Key | Description |
|-----|-------------|
| `concept_system` | System prompt for concept extraction |
| `diagram_system` | System prompt for diagram generation |
| `fix_mermaid_syntax` | User prompt template for fixing Mermaid syntax errors |

Note: User prompts with dynamic interpolation (`concept_user`, `diagram_from_concept_user`, `diagram_from_prompt_user`) remain as functions in the module since they require runtime string interpolation.

## Implementation Steps

### 1. Migration

```elixir
# priv/repo/migrations/TIMESTAMP_create_prompts.exs
defmodule DiagramForge.Repo.Migrations.CreatePrompts do
  use Ecto.Migration

  def change do
    create table(:prompts, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :key, :string, null: false
      add :content, :text, null: false
      add :description, :string

      timestamps(type: :utc_datetime)
    end

    create unique_index(:prompts, [:key])
  end
end
```

### 2. Schema

```elixir
# lib/diagram_forge/ai/prompt.ex
defmodule DiagramForge.AI.Prompt do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "prompts" do
    field :key, :string
    field :content, :string
    field :description, :string

    timestamps(type: :utc_datetime)
  end

  @required_fields ~w(key content)a
  @optional_fields ~w(description)a

  def changeset(prompt, attrs) do
    prompt
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> unique_constraint(:key)
  end
end
```

### 3. Context Functions

Add to `DiagramForge.AI` or create new context:

```elixir
# lib/diagram_forge/ai.ex
defmodule DiagramForge.AI do
  alias DiagramForge.AI.Prompt
  alias DiagramForge.Repo

  # Cache table name
  @cache_table :prompt_cache

  def start_cache do
    :ets.new(@cache_table, [:named_table, :public, read_concurrency: true])
  end

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

  def invalidate_cache(key) do
    :ets.delete(@cache_table, key)
  end

  def invalidate_all_cache do
    :ets.delete_all_objects(@cache_table)
  end

  # Default prompts (fallback)
  defp default_prompt("concept_system"), do: DiagramForge.AI.Prompts.concept_system_prompt()
  defp default_prompt("diagram_system"), do: DiagramForge.AI.Prompts.diagram_system_prompt()
  defp default_prompt(_), do: nil

  # CRUD
  def list_prompts, do: Repo.all(Prompt)

  def get_prompt!(id), do: Repo.get!(Prompt, id)

  def create_prompt(attrs) do
    %Prompt{}
    |> Prompt.changeset(attrs)
    |> Repo.insert()
    |> tap_invalidate_cache()
  end

  def update_prompt(%Prompt{} = prompt, attrs) do
    prompt
    |> Prompt.changeset(attrs)
    |> Repo.update()
    |> tap_invalidate_cache()
  end

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
end
```

### 4. Update Prompts Module

```elixir
# lib/diagram_forge/ai/prompts.ex
defmodule DiagramForge.AI.Prompts do
  @moduledoc """
  Prompt templates for AI-powered concept extraction and diagram generation.

  These are default prompts. Database-stored prompts take precedence when available.
  """

  # Keep existing module attributes as defaults
  @concept_system_prompt """
  ...existing prompt...
  """

  @diagram_system_prompt """
  ...existing prompt...
  """

  # Public functions now check DB first
  def concept_system_prompt do
    DiagramForge.AI.get_prompt("concept_system") || @concept_system_prompt
  end

  def diagram_system_prompt do
    DiagramForge.AI.get_prompt("diagram_system") || @diagram_system_prompt
  end

  # User prompts with interpolation remain as-is (no DB storage)
  def concept_user_prompt(text), do: # ... existing implementation
  def diagram_from_concept_user_prompt(concept, context), do: # ... existing
  def diagram_from_prompt_user_prompt(text), do: # ... existing
  def fix_mermaid_syntax_prompt(broken_mermaid, summary), do: # ... existing
end
```

### 5. Admin Page Behavior

The admin page should:

1. **List all known prompt keys** (from a hardcoded list of valid keys)
2. **Display effective content** - DB value if exists, otherwise hardcoded default
3. **On save** - INSERT if no DB record exists, UPDATE if it does
4. **Show indicator** - whether viewing default or customized version
5. **On delete** - DELETE from DB and go back to the hardcoded. Button grayed out if already default.

```elixir
# In the AI context, provide a function for admin to get all prompts with their status
def list_all_prompts_with_status do
  db_prompts = Repo.all(Prompt) |> Map.new(&{&1.key, &1})

  for {key, description} <- known_prompt_keys() do
    build_prompt_status(key, description, Map.get(db_prompts, key))
  end
end

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

defp known_prompt_keys do
  [
    {"concept_system", "System prompt for concept extraction from documents"},
    {"diagram_system", "System prompt for diagram generation"}
  ]
end
```

**No seed script needed** - the database starts empty and hardcoded defaults are used until an admin customizes a prompt.

### 6. Start Cache in Application

```elixir
# lib/diagram_forge/application.ex
def start(_type, _args) do
  # Start ETS cache for prompts
  DiagramForge.AI.start_cache()

  children = [
    # ... existing children
  ]
  # ...
end
```

### 7. Backpex Admin Resource

Note: Standard Backpex resource won't work directly because we need to:
- List ALL known prompt keys (even when no DB record exists)
- Show default vs customized indicator
- Disable "Reset to Default" button when already showing default

This likely requires a custom LiveView rather than standard Backpex resource:

```elixir
# lib/diagram_forge_web/live/admin/prompt_live.ex
defmodule DiagramForgeWeb.Admin.PromptLive do
  use DiagramForgeWeb, :live_view

  alias DiagramForge.AI

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, prompts: AI.list_all_prompts_with_status())}
  end

  @impl true
  def handle_event("edit", %{"key" => key}, socket) do
    # Navigate to edit page or open modal
    {:noreply, push_navigate(socket, to: ~p"/admin/prompts/#{key}/edit")}
  end

  @impl true
  def handle_event("reset_to_default", %{"key" => key}, socket) do
    # Find and delete the DB record
    prompt = socket.assigns.prompts |> Enum.find(&(&1.key == key))

    case prompt do
      %{source: :database, db_record: record} ->
        {:ok, _} = AI.delete_prompt(record)
        {:noreply, assign(socket, prompts: AI.list_all_prompts_with_status())}

      _ ->
        # Already at default, shouldn't happen due to UI
        {:noreply, socket}
    end
  end
end
```

Template showing "Reset to Default" button state:

```heex
<div :for={prompt <- @prompts} class="border rounded-lg p-4 mb-4">
  <div class="flex justify-between items-center">
    <div>
      <h3 class="font-semibold">{prompt.key}</h3>
      <p class="text-sm text-gray-500">{prompt.description}</p>
      <span class={[
        "text-xs px-2 py-1 rounded",
        prompt.source == :default && "bg-gray-100 text-gray-600",
        prompt.source == :database && "bg-blue-100 text-blue-600"
      ]}>
        {if prompt.source == :default, do: "Default", else: "Customized"}
      </span>
    </div>
    <div class="flex gap-2">
      <button phx-click="edit" phx-value-key={prompt.key}
              class="px-3 py-1 bg-blue-500 text-white rounded">
        Edit
      </button>
      <button phx-click="reset_to_default" phx-value-key={prompt.key}
              disabled={prompt.source == :default}
              class={[
                "px-3 py-1 rounded",
                prompt.source == :default && "bg-gray-200 text-gray-400 cursor-not-allowed",
                prompt.source == :database && "bg-red-500 text-white hover:bg-red-600"
              ]}>
        Reset to Default
      </button>
    </div>
  </div>
  <pre class="mt-2 p-2 bg-gray-50 text-sm overflow-x-auto max-h-40">{prompt.content}</pre>
</div>
```

### 8. Edit LiveView

```elixir
# lib/diagram_forge_web/live/admin/prompt_edit_live.ex
defmodule DiagramForgeWeb.Admin.PromptEditLive do
  use DiagramForgeWeb, :live_view

  alias DiagramForge.AI
  alias DiagramForge.AI.Prompt

  @impl true
  def mount(%{"key" => key}, _session, socket) do
    prompt_data = AI.get_prompt_with_status(key)

    form =
      case prompt_data.db_record do
        nil ->
          # No DB record yet - create changeset from default
          %Prompt{key: key, content: prompt_data.content, description: prompt_data.description}
          |> Prompt.changeset(%{})
          |> to_form()

        record ->
          record |> Prompt.changeset(%{}) |> to_form()
      end

    {:ok, assign(socket, prompt_data: prompt_data, form: form)}
  end

  @impl true
  def handle_event("save", %{"prompt" => params}, socket) do
    result =
      case socket.assigns.prompt_data.db_record do
        nil -> AI.create_prompt(Map.put(params, "key", socket.assigns.prompt_data.key))
        record -> AI.update_prompt(record, params)
      end

    case result do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Prompt saved successfully")
         |> push_navigate(to: ~p"/admin/prompts")}

      {:error, changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end
end
```

### 9. Add Routes

```elixir
# lib/diagram_forge_web/router.ex
# In admin scope
live "/prompts", Admin.PromptLive, :index
live "/prompts/:key/edit", Admin.PromptEditLive, :edit
```

## Cache Strategy

- **ETS table** for fast reads (prompts are read frequently during AI calls)
- **Invalidate on update/delete** - Clear specific key when prompt is edited or reset to default
- **Fallback to defaults** - If key not in DB, use hardcoded module default
- **No TTL needed** - Cache is invalidated explicitly on admin updates

## Testing Considerations

1. Test that DB prompts override defaults
2. Test cache invalidation on update and delete
3. Test fallback to defaults when DB prompt missing
4. Test "Reset to Default" deletes DB record and returns to hardcoded default
5. Test "Reset to Default" button is disabled when already at default
6. Mock prompts in existing AI tests

## Future Enhancements

- Version history for prompts (track changes)
- A/B testing different prompts
- Prompt templates with variable placeholders
- Import/export prompts as JSON
