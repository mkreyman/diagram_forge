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

### 5. Seed Default Prompts

```elixir
# priv/repo/seeds/prompts.exs
alias DiagramForge.AI.Prompt
alias DiagramForge.Repo

prompts = [
  %{
    key: "concept_system",
    description: "System prompt for concept extraction from documents",
    content: """
    You are a technical teaching assistant.
    ...rest of prompt...
    """
  },
  %{
    key: "diagram_system",
    description: "System prompt for diagram generation",
    content: """
    You generate small, interview-friendly technical diagrams in Mermaid syntax.
    ...rest of prompt...
    """
  }
]

for prompt_attrs <- prompts do
  case Repo.get_by(Prompt, key: prompt_attrs.key) do
    nil -> Repo.insert!(%Prompt{} |> Prompt.changeset(prompt_attrs))
    existing -> existing
  end
end
```

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

```elixir
# lib/diagram_forge_web/live/admin/prompt_resource.ex
defmodule DiagramForgeWeb.Admin.PromptResource do
  use Backpex.LiveResource,
    layout: {DiagramForgeWeb.Layouts, :admin},
    schema: DiagramForge.AI.Prompt,
    repo: DiagramForge.Repo,
    update_changeset: &DiagramForge.AI.Prompt.changeset/2,
    create_changeset: &DiagramForge.AI.Prompt.changeset/2

  @impl Backpex.LiveResource
  def singular_name, do: "Prompt"

  @impl Backpex.LiveResource
  def plural_name, do: "Prompts"

  @impl Backpex.LiveResource
  def fields do
    [
      key: %{
        module: Backpex.Fields.Text,
        label: "Key",
        searchable: true
      },
      description: %{
        module: Backpex.Fields.Text,
        label: "Description",
        searchable: true
      },
      content: %{
        module: Backpex.Fields.Textarea,
        label: "Content"
      },
      inserted_at: %{
        module: Backpex.Fields.DateTime,
        label: "Created"
      },
      updated_at: %{
        module: Backpex.Fields.DateTime,
        label: "Updated"
      }
    ]
  end
end
```

### 8. Add Route

```elixir
# lib/diagram_forge_web/router.ex
# In admin scope
backpex_routes(PromptResource, only: [:index, :show, :edit, :update])
```

## Cache Strategy

- **ETS table** for fast reads (prompts are read frequently during AI calls)
- **Invalidate on update** - Clear specific key when prompt is edited
- **Fallback to defaults** - If key not in DB, use hardcoded module default
- **No TTL needed** - Cache is invalidated explicitly on admin updates

## Testing Considerations

1. Test that DB prompts override defaults
2. Test cache invalidation on update
3. Test fallback to defaults when DB prompt missing
4. Mock prompts in existing AI tests

## Future Enhancements

- Version history for prompts (track changes)
- A/B testing different prompts
- Prompt templates with variable placeholders
- Import/export prompts as JSON
