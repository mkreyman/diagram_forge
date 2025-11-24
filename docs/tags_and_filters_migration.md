# DiagramForge Tags and Filters Migration

## Overview

This document provides a comprehensive implementation plan for migrating from a concept-based organization system to a pure tag-based system with saved filters. This migration removes the `concepts` table entirely and the `domain` field from diagrams, replacing them with a flexible tag-based organization model where saved filters act as dynamic "folders".

## Current State Analysis

### Existing Structure
- **Diagrams**: Have `concept_id` (FK to concepts), `domain` field, and `tags` array
- **Concepts**: Used as folders/categories for organizing diagrams
- **Tags**: Already exist on diagrams but underutilized

### Problems with Current Model
- Concepts create rigid hierarchy (diagram must belong to one concept)
- Domain field is redundant with tags
- Users need flexibility to view diagrams across multiple categories
- No way to save common filter combinations

---

## Data Model Changes

### 1. Remove Concepts Table Entirely

**Rationale**: Concepts are too rigid. Tags with saved filters provide the same organization without the constraints.

**Action**: Delete the entire `concepts` table and all references to it.

### 2. Remove Diagram Foreign Key to Concepts

**Current**: `diagrams.concept_id` (FK to concepts)

**Action**: Remove the field entirely from the schema and migration.

### 3. Remove Domain Field

**Current**: `diagrams.domain` (string field)

**Action**: Remove the field entirely. Domain values can be migrated to tags if needed.

**Rationale**: Domain is just another way of categorizing, which tags already provide.

### 4. Keep and Enhance Tags

**Current**: `diagrams.tags` (array of strings)

**Action**: Keep as-is. This is the foundation of the new organization system.

**Enhancement**: Add UI for tag autocomplete, tag cloud, and tag-based filtering.

### 5. Create saved_filters Table

**Purpose**: Allow users to save common tag combinations as named filters for quick access.

**Fields**:
- `id` (binary_id, primary key)
- `user_id` (binary_id, FK to users, not null)
- `name` (string, not null) - e.g., "Interview Prep", "OAuth Project"
- `tag_filter` (array of strings, not null) - e.g., ["elixir", "oauth"]
- `is_pinned` (boolean, not null, default: true) - Show in sidebar
- `sort_order` (integer, not null) - For ordering pinned filters in sidebar
- `inserted_at` (timestamp)
- `updated_at` (timestamp)

**Constraints**:
- Index on `user_id` for efficient "my filters" queries
- Index on `[user_id, is_pinned]` for filtering pinned vs unpinned
- Index on `[user_id, sort_order]` for ordering pinned filters
- Unique constraint on `[user_id, name]` to prevent duplicate filter names

**Semantics**:
- `is_pinned: true` - Filter appears in sidebar for quick access
- `is_pinned: false` - Filter exists but hidden from sidebar (saved for later)
- `tag_filter: []` - Empty array means "show all diagrams"
- `sort_order` - Lower numbers appear first in sidebar

---

## Migration Strategy

### Philosophy: Modify Existing Migrations

Since this is early development:
1. MODIFY existing migration files (don't create new ones where possible)
2. User will run `mix ecto.reset` in dev and test
3. Cleaner migration history
4. No production data to preserve

### Migration Changes Required

#### File: `priv/repo/migrations/20251121181621_create_diagrams.exs`

**Changes**:
1. Remove `concept_id` foreign key
2. Remove `domain` field
3. Keep `tags` field (already exists)

```elixir
defmodule DiagramForge.Repo.Migrations.CreateDiagrams do
  use Ecto.Migration

  def change do
    create table(:diagrams, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :document_id, references(:documents, type: :binary_id, on_delete: :nilify_all)
      add :forked_from_id, references(:diagrams, type: :binary_id, on_delete: :nilify_all)

      add :slug, :string, null: false
      add :title, :string, null: false
      add :tags, {:array, :string}, default: []
      add :format, :string, null: false, default: "mermaid"
      add :diagram_source, :text, null: false
      add :summary, :text
      add :notes_md, :text
      add :visibility, :string, null: false, default: "unlisted"

      timestamps()
    end

    create unique_index(:diagrams, [:slug])
    create index(:diagrams, [:document_id])
    create index(:diagrams, [:forked_from_id])
    create index(:diagrams, [:visibility])
    # GIN index for efficient tag queries
    create index(:diagrams, [:tags], using: :gin)
  end
end
```

**Note**: Added GIN index on `tags` for efficient array queries.

#### File: `priv/repo/migrations/20251121181613_create_concepts.exs`

**Action**: DELETE this file entirely.

**Rationale**: We're removing concepts completely. No need for the table.

#### New File: `priv/repo/migrations/NNNNNNNNNNNNNN_create_saved_filters.exs`

**Purpose**: Create saved_filters table for storing user filter preferences.

```elixir
defmodule DiagramForge.Repo.Migrations.CreateSavedFilters do
  use Ecto.Migration

  def change do
    create table(:saved_filters, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all),
        null: false

      add :name, :string, null: false
      add :tag_filter, {:array, :string}, null: false, default: []
      add :is_pinned, :boolean, null: false, default: true
      add :sort_order, :integer, null: false, default: 0

      timestamps()
    end

    # Efficient queries for user's filters
    create index(:saved_filters, [:user_id])

    # Efficient queries for pinned filters
    create index(:saved_filters, [:user_id, :is_pinned])

    # Efficient queries for ordering pinned filters
    create index(:saved_filters, [:user_id, :sort_order])

    # Prevent duplicate filter names per user
    create unique_index(:saved_filters, [:user_id, :name])
  end
end
```

### Data Migration from Concepts

**Optional**: Convert existing concepts to pinned saved filters.

**Strategy**:
1. For each user, find all concepts they own
2. Create a saved filter for each concept with the concept name
3. Add the concept name as a tag to all diagrams that belonged to that concept
4. Pin all migrated filters

**Implementation**: Add a migration task (not required for `mix ecto.reset`):

```elixir
defmodule DiagramForge.Repo.Migrations.MigrateConceptsToFilters do
  use Ecto.Migration

  def up do
    # This would only run in production
    # For dev, we're using mix ecto.reset, so this is optional

    # Example logic (not executed in dev):
    # 1. Find all concepts with owner_id
    # 2. For each concept:
    #    a. Create saved_filter with concept name
    #    b. Add concept name as tag to all diagrams with that concept_id
    #    c. Pin the filter
  end

  def down do
    # No rollback needed for dev
  end
end
```

---

## Schema Changes

### 1. Update `lib/diagram_forge/diagrams/diagram.ex`

**Changes**:
- Remove `belongs_to :concept`
- Remove `field :domain`
- Keep `field :tags`
- Update changeset to remove concept_id and domain

```elixir
defmodule DiagramForge.Diagrams.Diagram do
  @moduledoc """
  Schema for generated Mermaid diagrams.

  Diagrams are LLM-generated visual representations of technical concepts,
  stored in Mermaid format with supporting metadata.

  ## Organization

  Diagrams are organized using tags. Users can create saved filters to
  quickly view diagrams matching specific tag combinations.

  ## Ownership

  Diagrams support multiple users through the `user_diagrams` join table:
  - Users with `is_owner: true` can edit and delete
  - Users with `is_owner: false` have bookmarked/saved the diagram

  ## Visibility

  - `:private` - Only owner can view (even via permalink)
  - `:unlisted` - Anyone with link can view (default)
  - `:public` - Anyone can view + discoverable in public feed
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "diagrams" do
    belongs_to :document, DiagramForge.Diagrams.Document
    belongs_to :forked_from, __MODULE__

    many_to_many :users, DiagramForge.Accounts.User,
      join_through: DiagramForge.Diagrams.UserDiagram

    field :slug, :string
    field :title, :string

    field :tags, {:array, :string}, default: []

    field :format, Ecto.Enum, values: [:mermaid, :plantuml], default: :mermaid
    field :visibility, Ecto.Enum,
      values: [:private, :unlisted, :public],
      default: :unlisted

    field :diagram_source, :string
    field :summary, :string
    field :notes_md, :string

    timestamps()
  end

  def changeset(diagram, attrs) do
    diagram
    |> cast(attrs, [
      :document_id,
      :forked_from_id,
      :slug,
      :title,
      :tags,
      :format,
      :visibility,
      :diagram_source,
      :summary,
      :notes_md
    ])
    |> validate_required([:title, :format, :diagram_source, :slug])
    |> validate_inclusion(:visibility, [:private, :unlisted, :public])
    |> unique_constraint(:slug)
    |> foreign_key_constraint(:document_id)
    |> foreign_key_constraint(:forked_from_id)
  end
end
```

### 2. Delete `lib/diagram_forge/diagrams/concept.ex`

**Action**: Delete this file entirely.

### 3. Create `lib/diagram_forge/diagrams/saved_filter.ex`

**New Schema**: Saved filter for tag-based organization.

```elixir
defmodule DiagramForge.Diagrams.SavedFilter do
  @moduledoc """
  Schema for saved tag filters.

  Saved filters allow users to create named combinations of tags for quick
  access to relevant diagrams. Pinned filters appear in the sidebar for
  easy navigation.

  ## Examples

  - name: "Interview Prep", tag_filter: ["elixir", "patterns"], is_pinned: true
  - name: "OAuth Project", tag_filter: ["oauth", "security"], is_pinned: true
  - name: "Archived Ideas", tag_filter: ["archive"], is_pinned: false
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "saved_filters" do
    belongs_to :user, DiagramForge.Accounts.User

    field :name, :string
    field :tag_filter, {:array, :string}, default: []
    field :is_pinned, :boolean, default: true
    field :sort_order, :integer, default: 0

    timestamps()
  end

  def changeset(saved_filter, attrs) do
    saved_filter
    |> cast(attrs, [:user_id, :name, :tag_filter, :is_pinned, :sort_order])
    |> validate_required([:user_id, :name, :tag_filter, :is_pinned, :sort_order])
    |> unique_constraint([:user_id, :name])
    |> foreign_key_constraint(:user_id)
  end
end
```

### 4. Update `lib/diagram_forge/accounts/user.ex`

**Changes**:
- Remove `has_many :owned_concepts`
- Add `has_many :saved_filters`

```elixir
defmodule DiagramForge.Accounts.User do
  @moduledoc """
  Schema for users authenticated via GitHub OAuth.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "users" do
    field :email, :string
    field :name, :string
    field :provider, :string, default: "github"
    field :provider_uid, :string
    field :provider_token, DiagramForge.Vault.EncryptedBinary
    field :avatar_url, :string
    field :last_sign_in_at, :utc_datetime
    field :show_public_diagrams, :boolean, default: false

    many_to_many :diagrams, DiagramForge.Diagrams.Diagram,
      join_through: DiagramForge.Diagrams.UserDiagram

    has_many :saved_filters, DiagramForge.Diagrams.SavedFilter, foreign_key: :user_id

    timestamps()
  end

  def changeset(user, attrs) do
    user
    |> cast(attrs, [
      :email,
      :name,
      :provider,
      :provider_uid,
      :provider_token,
      :avatar_url,
      :show_public_diagrams
    ])
    |> validate_required([:email, :provider, :provider_uid])
    |> validate_format(:email, ~r/^[^\s]+@[^\s]+$/)
    |> unique_constraint(:email)
    |> unique_constraint([:provider, :provider_uid])
  end

  def sign_in_changeset(user, attrs \\ %{}) do
    user
    |> cast(attrs, [:last_sign_in_at])
    |> put_change(:last_sign_in_at, DateTime.utc_now() |> DateTime.truncate(:second))
  end

  def preferences_changeset(user, attrs) do
    user
    |> cast(attrs, [:show_public_diagrams])
    |> validate_required([:show_public_diagrams])
  end
end
```

---

## Context Functions (lib/diagram_forge/diagrams.ex)

### Tag Management Functions

```elixir
@doc """
Lists all unique tags across all diagrams a user can access.

Used for tag autocomplete and tag cloud.
"""
def list_available_tags(user_id) do
  # Get all tags from user's owned and bookmarked diagrams
  query =
    from d in Diagram,
      join: ud in UserDiagram,
      on: ud.diagram_id == d.id,
      where: ud.user_id == ^user_id,
      select: d.tags

  Repo.all(query)
  |> List.flatten()
  |> Enum.uniq()
  |> Enum.sort()
end

@doc """
Gets tag counts for a user's accessible diagrams.

Returns a map of tag => count for displaying tag clouds.
"""
def get_tag_counts(user_id) do
  query =
    from d in Diagram,
      join: ud in UserDiagram,
      on: ud.diagram_id == d.id,
      where: ud.user_id == ^user_id,
      select: d.tags

  Repo.all(query)
  |> List.flatten()
  |> Enum.frequencies()
end

@doc """
Adds tags to a diagram.
"""
def add_tags(%Diagram{} = diagram, new_tags, user_id) when is_list(new_tags) do
  if can_edit_diagram?(diagram, %{id: user_id}) do
    current_tags = diagram.tags || []
    updated_tags = (current_tags ++ new_tags) |> Enum.uniq()

    diagram
    |> Diagram.changeset(%{tags: updated_tags})
    |> Repo.update()
  else
    {:error, :unauthorized}
  end
end

@doc """
Removes tags from a diagram.
"""
def remove_tags(%Diagram{} = diagram, tags_to_remove, user_id) when is_list(tags_to_remove) do
  if can_edit_diagram?(diagram, %{id: user_id}) do
    current_tags = diagram.tags || []
    updated_tags = current_tags -- tags_to_remove

    diagram
    |> Diagram.changeset(%{tags: updated_tags})
    |> Repo.update()
  else
    {:error, :unauthorized}
  end
end
```

### Saved Filter Functions

```elixir
@doc """
Lists all saved filters for a user.
"""
def list_saved_filters(user_id) do
  Repo.all(
    from f in SavedFilter,
      where: f.user_id == ^user_id,
      order_by: [asc: f.sort_order]
  )
end

@doc """
Lists only pinned saved filters for a user (for sidebar display).
"""
def list_pinned_filters(user_id) do
  Repo.all(
    from f in SavedFilter,
      where: f.user_id == ^user_id and f.is_pinned == true,
      order_by: [asc: f.sort_order]
  )
end

@doc """
Gets a saved filter by ID.
"""
def get_saved_filter!(id), do: Repo.get!(SavedFilter, id)

@doc """
Creates a saved filter for a user.
"""
def create_saved_filter(attrs, user_id) do
  # Get current max sort_order for user
  max_sort_order =
    Repo.one(
      from f in SavedFilter,
        where: f.user_id == ^user_id,
        select: max(f.sort_order)
    ) || 0

  attrs =
    attrs
    |> Map.put(:user_id, user_id)
    |> Map.put_new(:sort_order, max_sort_order + 1)

  %SavedFilter{}
  |> SavedFilter.changeset(attrs)
  |> Repo.insert()
end

@doc """
Updates a saved filter (only owner can update).
"""
def update_saved_filter(%SavedFilter{} = filter, attrs, user_id) do
  if filter.user_id == user_id do
    filter
    |> SavedFilter.changeset(attrs)
    |> Repo.update()
  else
    {:error, :unauthorized}
  end
end

@doc """
Deletes a saved filter (only owner can delete).
"""
def delete_saved_filter(%SavedFilter{} = filter, user_id) do
  if filter.user_id == user_id do
    Repo.delete(filter)
  else
    {:error, :unauthorized}
  end
end

@doc """
Reorders saved filters by updating sort_order.

Takes a list of filter IDs in the desired order.
"""
def reorder_saved_filters(filter_ids, user_id) when is_list(filter_ids) do
  Repo.transaction(fn ->
    filter_ids
    |> Enum.with_index()
    |> Enum.each(fn {filter_id, index} ->
      filter = Repo.get!(SavedFilter, filter_id)

      if filter.user_id == user_id do
        filter
        |> SavedFilter.changeset(%{sort_order: index})
        |> Repo.update!()
      else
        Repo.rollback(:unauthorized)
      end
    end)
  end)
end
```

### Tag-Based Query Functions

```elixir
@doc """
Lists diagrams matching a tag filter.

Empty tag list means "show all diagrams".
Tags are combined with AND logic (diagram must have ALL tags).
"""
def list_diagrams_by_tags(user_id, tags, ownership \\ :all)

def list_diagrams_by_tags(user_id, [], ownership) do
  # Empty tags means show all
  case ownership do
    :owned -> list_owned_diagrams(user_id)
    :bookmarked -> list_bookmarked_diagrams(user_id)
    :all -> list_owned_diagrams(user_id) ++ list_bookmarked_diagrams(user_id)
  end
end

def list_diagrams_by_tags(user_id, tags, ownership) when is_list(tags) do
  # Build base query with ownership filter
  base_query =
    from d in Diagram,
      join: ud in UserDiagram,
      on: ud.diagram_id == d.id,
      where: ud.user_id == ^user_id

  # Add ownership filter
  query =
    case ownership do
      :owned -> from [d, ud] in base_query, where: ud.is_owner == true
      :bookmarked -> from [d, ud] in base_query, where: ud.is_owner == false
      :all -> base_query
    end

  # Add tag filter (must have ALL tags)
  query =
    Enum.reduce(tags, query, fn tag, acc ->
      from [d, ud] in acc,
        where: ^tag in d.tags
    end)

  # Execute with ordering
  query
  |> order_by([d], desc: d.inserted_at)
  |> Repo.all()
end

@doc """
Lists diagrams matching a saved filter.
"""
def list_diagrams_by_saved_filter(user_id, %SavedFilter{} = filter) do
  list_diagrams_by_tags(user_id, filter.tag_filter, :all)
end

@doc """
Gets counts for a saved filter (how many diagrams match).
"""
def get_saved_filter_count(user_id, %SavedFilter{} = filter) do
  diagrams = list_diagrams_by_tags(user_id, filter.tag_filter, :all)
  length(diagrams)
end
```

### Remove Concept-Related Functions

Delete all functions that reference concepts:
- `list_owned_concepts/1`
- `group_diagrams_by_concept/2`
- `user_owns_concept?/2`
- `can_delete_concept?/2`
- `create_concept_for_user/2`
- `update_concept/3`
- `delete_concept/2`

### Update Fork and Bookmark Functions

```elixir
@doc """
Forks a diagram.

Creates a new diagram with:
- All data copied from original
- Tags copied from original (user can edit after)
- New ID generated
- forked_from_id set to original
- New user_diagrams entry with is_owner: true
"""
def fork_diagram(original_id, user_id) do
  Repo.transaction(fn ->
    original = Repo.get!(Diagram, original_id)

    # Create new diagram with copied data
    new_diagram_attrs = %{
      title: original.title,
      diagram_source: original.diagram_source,
      summary: original.summary,
      notes_md: original.notes_md,
      tags: original.tags,  # Copy tags from original
      format: original.format,
      slug: generate_unique_slug(original.slug),
      visibility: :unlisted,
      forked_from_id: original.id
    }

    case create_diagram_for_user(new_diagram_attrs, user_id) do
      {:ok, diagram} -> diagram
      {:error, reason} -> Repo.rollback(reason)
    end
  end)
end

@doc """
Bookmarks/saves a diagram for a user.

Creates user_diagrams entry with is_owner: false.
User can add their own tags to bookmarked diagrams.
"""
def bookmark_diagram(diagram_id, user_id) do
  user_diagram_changeset =
    UserDiagram.changeset(%UserDiagram{}, %{
      user_id: user_id,
      diagram_id: diagram_id,
      is_owner: false
    })

  Repo.insert(user_diagram_changeset)
end
```

---

## LiveView Changes

### Sidebar Structure Requirements

```
MY DIAGRAMS (12)
Filter: [tag input with autocomplete]
[Active filters shown as removable chips]
[Save Current Filter] button

PINNED FILTERS
├─ Interview Prep (5)     [edit] [unpin]
├─ OAuth Project (8)      [edit] [unpin]
├─ Elixir Learning (3)    [edit] [unpin]
[Reorder with drag handles]

[List of diagrams matching current filter]

FORKED DIAGRAMS (4)
[Similar structure with tag filter]

──────────────
☐ Show All Public Diagrams
```

### Main LiveView: `lib/diagram_forge_web/live/diagram_studio_live.ex`

**Key Changes**:
1. Remove all concept-related code
2. Add tag filter state
3. Add saved filter management
4. Handle tag input and filtering

**Mount Function**:
```elixir
def mount(_params, _session, socket) do
  current_user = socket.assigns[:current_user]

  socket =
    socket
    |> assign(:current_user, current_user)
    |> assign(:active_tag_filter, [])
    |> assign(:available_tags, [])
    |> assign(:tag_counts, %{})
    |> assign(:pinned_filters, [])
    |> load_diagrams()
    |> load_tags()
    |> load_filters()
    |> assign(:show_public_diagrams, current_user && current_user.show_public_diagrams)

  {:ok, socket}
end

defp load_diagrams(socket) do
  user_id = socket.assigns.current_user && socket.assigns.current_user.id
  tag_filter = socket.assigns[:active_tag_filter] || []

  owned = if user_id, do: Diagrams.list_diagrams_by_tags(user_id, tag_filter, :owned), else: []
  bookmarked = if user_id, do: Diagrams.list_diagrams_by_tags(user_id, tag_filter, :bookmarked), else: []

  public =
    if socket.assigns[:show_public_diagrams] do
      Diagrams.list_public_diagrams()
    else
      []
    end

  socket
  |> assign(:owned_diagrams, owned)
  |> assign(:bookmarked_diagrams, bookmarked)
  |> assign(:public_diagrams, public)
  |> assign(:owned_empty?, owned == [])
  |> assign(:bookmarked_empty?, bookmarked == [])
end

defp load_tags(socket) do
  user_id = socket.assigns.current_user && socket.assigns.current_user.id

  if user_id do
    socket
    |> assign(:available_tags, Diagrams.list_available_tags(user_id))
    |> assign(:tag_counts, Diagrams.get_tag_counts(user_id))
  else
    socket
  end
end

defp load_filters(socket) do
  user_id = socket.assigns.current_user && socket.assigns.current_user.id

  if user_id do
    socket
    |> assign(:pinned_filters, Diagrams.list_pinned_filters(user_id))
  else
    socket
  end
end
```

**Event Handlers**:
```elixir
# Tag filtering
def handle_event("add_tag_to_filter", %{"tag" => tag}, socket) do
  current_filter = socket.assigns.active_tag_filter
  new_filter = (current_filter ++ [tag]) |> Enum.uniq()

  socket =
    socket
    |> assign(:active_tag_filter, new_filter)
    |> load_diagrams()

  {:noreply, socket}
end

def handle_event("remove_tag_from_filter", %{"tag" => tag}, socket) do
  current_filter = socket.assigns.active_tag_filter
  new_filter = current_filter -- [tag]

  socket =
    socket
    |> assign(:active_tag_filter, new_filter)
    |> load_diagrams()

  {:noreply, socket}
end

def handle_event("clear_filter", _params, socket) do
  socket =
    socket
    |> assign(:active_tag_filter, [])
    |> load_diagrams()

  {:noreply, socket}
end

# Saved filter management
def handle_event("apply_saved_filter", %{"id" => filter_id}, socket) do
  filter = Diagrams.get_saved_filter!(filter_id)

  socket =
    socket
    |> assign(:active_tag_filter, filter.tag_filter)
    |> load_diagrams()

  {:noreply, socket}
end

def handle_event("show_save_filter_modal", _params, socket) do
  {:noreply, assign(socket, :show_save_filter_modal, true)}
end

def handle_event("save_current_filter", %{"name" => name}, socket) do
  user_id = socket.assigns.current_user.id
  tag_filter = socket.assigns.active_tag_filter

  case Diagrams.create_saved_filter(%{name: name, tag_filter: tag_filter}, user_id) do
    {:ok, _filter} ->
      socket =
        socket
        |> assign(:show_save_filter_modal, false)
        |> load_filters()
        |> put_flash(:info, "Filter saved successfully")

      {:noreply, socket}

    {:error, %Ecto.Changeset{} = changeset} ->
      {:noreply, assign(socket, :filter_changeset, changeset)}
  end
end

def handle_event("edit_filter", %{"id" => id}, socket) do
  filter = Diagrams.get_saved_filter!(id)
  {:noreply, assign(socket, :editing_filter, filter)}
end

def handle_event("save_filter_edit", %{"filter" => params}, socket) do
  filter = socket.assigns.editing_filter
  user_id = socket.assigns.current_user.id

  case Diagrams.update_saved_filter(filter, params, user_id) do
    {:ok, _updated} ->
      socket =
        socket
        |> assign(:editing_filter, nil)
        |> load_filters()
        |> put_flash(:info, "Filter updated successfully")

      {:noreply, socket}

    {:error, %Ecto.Changeset{} = changeset} ->
      {:noreply, assign(socket, :filter_changeset, changeset)}

    {:error, :unauthorized} ->
      {:noreply, put_flash(socket, :error, "Unauthorized")}
  end
end

def handle_event("delete_filter", %{"id" => id}, socket) do
  filter = Diagrams.get_saved_filter!(id)
  user_id = socket.assigns.current_user.id

  case Diagrams.delete_saved_filter(filter, user_id) do
    {:ok, _} ->
      socket =
        socket
        |> load_filters()
        |> put_flash(:info, "Filter deleted successfully")

      {:noreply, socket}

    {:error, :unauthorized} ->
      {:noreply, put_flash(socket, :error, "Unauthorized")}
  end
end

def handle_event("toggle_filter_pin", %{"id" => id}, socket) do
  filter = Diagrams.get_saved_filter!(id)
  user_id = socket.assigns.current_user.id

  case Diagrams.update_saved_filter(filter, %{is_pinned: !filter.is_pinned}, user_id) do
    {:ok, _} ->
      socket =
        socket
        |> load_filters()
        |> put_flash(:info, "Filter #{if filter.is_pinned, do: "unpinned", else: "pinned"}")

      {:noreply, socket}

    {:error, :unauthorized} ->
      {:noreply, put_flash(socket, :error, "Unauthorized")}
  end
end

def handle_event("reorder_filters", %{"ids" => ids}, socket) do
  user_id = socket.assigns.current_user.id

  case Diagrams.reorder_saved_filters(ids, user_id) do
    {:ok, _} ->
      socket =
        socket
        |> load_filters()

      {:noreply, socket}

    {:error, :unauthorized} ->
      {:noreply, put_flash(socket, :error, "Unauthorized")}
  end
end

# Tag management on diagrams
def handle_event("add_tags_to_diagram", %{"id" => id, "tags" => tags_str}, socket) do
  diagram = Diagrams.get_diagram!(id)
  user_id = socket.assigns.current_user.id
  tags = String.split(tags_str, ",") |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == ""))

  case Diagrams.add_tags(diagram, tags, user_id) do
    {:ok, _} ->
      socket =
        socket
        |> load_diagrams()
        |> load_tags()
        |> put_flash(:info, "Tags added successfully")

      {:noreply, socket}

    {:error, :unauthorized} ->
      {:noreply, put_flash(socket, :error, "Unauthorized")}
  end
end

def handle_event("remove_tag_from_diagram", %{"id" => id, "tag" => tag}, socket) do
  diagram = Diagrams.get_diagram!(id)
  user_id = socket.assigns.current_user.id

  case Diagrams.remove_tags(diagram, [tag], user_id) do
    {:ok, _} ->
      socket =
        socket
        |> load_diagrams()
        |> load_tags()
        |> put_flash(:info, "Tag removed successfully")

      {:noreply, socket}

    {:error, :unauthorized} ->
      {:noreply, put_flash(socket, :error, "Unauthorized")}
  end
end

# Fork and bookmark (no concept selection)
def handle_event("fork_diagram", %{"id" => id}, socket) do
  user_id = socket.assigns.current_user.id

  case Diagrams.fork_diagram(id, user_id) do
    {:ok, _forked} ->
      socket =
        socket
        |> load_diagrams()
        |> put_flash(:info, "Diagram forked successfully")

      {:noreply, socket}

    {:error, _reason} ->
      {:noreply, put_flash(socket, :error, "Failed to fork diagram")}
  end
end

def handle_event("bookmark_diagram", %{"id" => id}, socket) do
  user_id = socket.assigns.current_user.id

  case Diagrams.bookmark_diagram(id, user_id) do
    {:ok, _} ->
      socket =
        socket
        |> load_diagrams()
        |> put_flash(:info, "Diagram bookmarked successfully")

      {:noreply, socket}

    {:error, _reason} ->
      {:noreply, put_flash(socket, :error, "Failed to bookmark diagram")}
  end
end
```

---

## UI Components

### Tag Input with Autocomplete

```elixir
attr :available_tags, :list, required: true
attr :on_add, :string, required: true

def tag_input_with_autocomplete(assigns) do
  ~H"""
  <div class="relative">
    <input
      type="text"
      id="tag-input"
      placeholder="Add tags..."
      phx-keydown="tag_input_keydown"
      phx-blur="tag_input_blur"
      class="w-full px-3 py-2 border rounded-lg"
      autocomplete="off"
      list="tag-suggestions"
    />

    <datalist id="tag-suggestions">
      <option :for={tag <- @available_tags} value={tag}>{tag}</option>
    </datalist>
  </div>
  """
end
```

### Active Filter Chips

```elixir
attr :active_tags, :list, required: true
attr :on_remove, :string, required: true

def active_filter_chips(assigns) do
  ~H"""
  <div class="flex flex-wrap gap-2">
    <div :for={tag <- @active_tags} class="inline-flex items-center gap-1 px-3 py-1 bg-blue-100 text-blue-800 rounded-full text-sm">
      <span>{tag}</span>
      <button
        type="button"
        phx-click={@on_remove}
        phx-value-tag={tag}
        class="hover:bg-blue-200 rounded-full p-0.5"
      >
        <.icon name="hero-x-mark" class="w-3 h-3" />
      </button>
    </div>

    <%= if @active_tags != [] do %>
      <button
        type="button"
        phx-click="clear_filter"
        class="text-sm text-gray-500 hover:text-gray-700"
      >
        Clear all
      </button>
    <% end %>
  </div>
  """
end
```

### Tag Cloud

```elixir
attr :tag_counts, :map, required: true
attr :on_tag_click, :string, required: true

def tag_cloud(assigns) do
  ~H"""
  <div class="flex flex-wrap gap-2">
    <button
      :for={{tag, count} <- @tag_counts}
      type="button"
      phx-click={@on_tag_click}
      phx-value-tag={tag}
      class="inline-flex items-center gap-1 px-3 py-1 bg-gray-100 hover:bg-gray-200 rounded-full text-sm"
    >
      <span>{tag}</span>
      <span class="text-xs text-gray-500">({count})</span>
    </button>
  </div>
  """
end
```

### Saved Filter Item

```elixir
attr :filter, :map, required: true
attr :count, :integer, required: true

def saved_filter_item(assigns) do
  ~H"""
  <div class="flex items-center justify-between py-2 px-3 hover:bg-gray-50 rounded group">
    <button
      type="button"
      phx-click="apply_saved_filter"
      phx-value-id={@filter.id}
      class="flex-1 flex items-center gap-2 text-left"
    >
      <span class="font-medium">{@filter.name}</span>
      <span class="text-sm text-gray-500">({@count})</span>
    </button>

    <div class="flex gap-1 opacity-0 group-hover:opacity-100 transition-opacity">
      <button
        type="button"
        phx-click="edit_filter"
        phx-value-id={@filter.id}
        class="p-1 hover:bg-gray-200 rounded"
        title="Edit filter"
      >
        <.icon name="hero-pencil" class="w-4 h-4" />
      </button>

      <button
        type="button"
        phx-click="toggle_filter_pin"
        phx-value-id={@filter.id}
        class="p-1 hover:bg-gray-200 rounded"
        title={if @filter.is_pinned, do: "Unpin", else: "Pin"}
      >
        <.icon name={if @filter.is_pinned, do: "hero-bookmark-solid", else: "hero-bookmark"} class="w-4 h-4" />
      </button>

      <button
        type="button"
        phx-click="delete_filter"
        phx-value-id={@filter.id}
        data-confirm="Delete this filter?"
        class="p-1 hover:bg-red-200 rounded text-red-600"
        title="Delete filter"
      >
        <.icon name="hero-trash" class="w-4 h-4" />
      </button>
    </div>
  </div>
  """
end
```

### Save Filter Modal

```elixir
attr :on_save, :string, required: true
attr :on_cancel, :string, required: true

def save_filter_modal(assigns) do
  ~H"""
  <div class="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center z-50">
    <div class="bg-white rounded-lg p-6 max-w-md w-full">
      <h2 class="text-xl font-bold mb-4">Save Current Filter</h2>

      <.form for={%{}} id="save-filter-form" phx-submit={@on_save}>
        <.input
          name="name"
          type="text"
          label="Filter Name"
          placeholder="e.g., Interview Prep"
          required
        />

        <div class="flex justify-end gap-2 mt-6">
          <button
            type="button"
            phx-click={@on_cancel}
            class="px-4 py-2 bg-gray-200 rounded hover:bg-gray-300"
          >
            Cancel
          </button>
          <button
            type="submit"
            class="px-4 py-2 bg-blue-600 text-white rounded hover:bg-blue-700"
          >
            Save Filter
          </button>
        </div>
      </.form>
    </div>
  </div>
  """
end
```

### Diagram Item with Tags

```elixir
attr :diagram, :map, required: true
attr :user, :map, required: true

def diagram_item_with_tags(assigns) do
  ~H"""
  <div class="p-4 border rounded-lg hover:shadow-lg transition-shadow">
    <.link navigate={~p"/diagrams/#{@diagram.id}"} class="block">
      <h3 class="text-lg font-semibold mb-2">{@diagram.title}</h3>
    </.link>

    <div class="flex flex-wrap gap-1 mb-2">
      <span :for={tag <- @diagram.tags} class="inline-block px-2 py-1 bg-gray-100 text-gray-700 rounded text-xs">
        {tag}
      </span>
    </div>

    <div class="flex gap-2 mt-2">
      <%= if Diagrams.can_edit_diagram?(@diagram, @user) do %>
        <button
          phx-click="edit_diagram"
          phx-value-id={@diagram.id}
          class="text-sm text-blue-600 hover:text-blue-800"
        >
          Edit
        </button>
        <button
          phx-click="delete_diagram"
          phx-value-id={@diagram.id}
          data-confirm="Delete this diagram?"
          class="text-sm text-red-600 hover:text-red-800"
        >
          Delete
        </button>
      <% else %>
        <button
          phx-click="remove_bookmark"
          phx-value-id={@diagram.id}
          class="text-sm text-gray-600 hover:text-gray-800"
        >
          Remove
        </button>
      <% end %>

      <button
        phx-click="fork_diagram"
        phx-value-id={@diagram.id}
        class="text-sm text-blue-600 hover:text-blue-800"
      >
        Fork
      </button>
    </div>
  </div>
  """
end
```

---

## Test Coverage

### Test Files to Create/Modify

#### 1. `test/diagram_forge/diagrams_test.exs`

**Test Cases**:
- Tag management functions
  - `list_available_tags/1` returns unique tags
  - `get_tag_counts/1` returns correct counts
  - `add_tags/3` adds tags to diagram
  - `remove_tags/3` removes tags from diagram
  - Authorization checks for tag operations

- Saved filter CRUD
  - `create_saved_filter/2` creates filter
  - `update_saved_filter/3` only allows owner
  - `delete_saved_filter/2` only allows owner
  - `list_pinned_filters/1` returns only pinned
  - `reorder_saved_filters/2` updates sort_order
  - Unique constraint on [user_id, name]

- Tag-based queries
  - `list_diagrams_by_tags/3` with empty tags shows all
  - `list_diagrams_by_tags/3` with tags filters correctly
  - `list_diagrams_by_tags/3` with ownership filter
  - `list_diagrams_by_saved_filter/2`
  - `get_saved_filter_count/2`

- Fork and bookmark without concepts
  - `fork_diagram/2` copies tags
  - `bookmark_diagram/2` creates bookmark

#### 2. `test/diagram_forge_web/live/diagram_studio_live_test.exs`

**Test Cases**:
- Tag filtering
  - Add tag to filter updates diagrams list
  - Remove tag from filter updates diagrams list
  - Clear filter shows all diagrams
  - Apply saved filter sets active filter

- Saved filter management
  - Save current filter creates saved filter
  - Edit filter updates name/tags
  - Delete filter removes it
  - Pin/unpin filter updates is_pinned
  - Reorder filters updates sort_order

- Tag management on diagrams
  - Add tags to diagram updates tags
  - Remove tag from diagram updates tags
  - Tag autocomplete shows available tags
  - Tag cloud shows counts

- Fork and bookmark
  - Fork copies tags from original
  - Bookmark doesn't require concept selection

#### 3. `test/diagram_forge/diagrams/saved_filter_test.exs`

**Test Cases**:
- Changeset validation
- Unique constraint on [user_id, name]
- Foreign key constraints

#### 4. `test/support/fixtures/diagrams_fixtures.ex`

**Add Fixtures**:
```elixir
def saved_filter_fixture(attrs \\ %{}) do
  user = attrs[:user] || DiagramForge.AccountsFixtures.user_fixture()

  {:ok, filter} =
    %DiagramForge.Diagrams.SavedFilter{}
    |> DiagramForge.Diagrams.SavedFilter.changeset(
      Enum.into(attrs, %{
        user_id: user.id,
        name: "Test Filter #{System.unique_integer()}",
        tag_filter: ["elixir", "test"],
        is_pinned: true,
        sort_order: 0
      })
    )
    |> DiagramForge.Repo.insert()

  filter
end

def diagram_with_tags_fixture(attrs \\ %{}) do
  user = attrs[:user] || DiagramForge.AccountsFixtures.user_fixture()

  attrs =
    attrs
    |> Map.put_new(:tags, ["elixir", "phoenix", "test"])

  diagram_fixture(attrs)
end
```

---

## Implementation Phases

### Phase 1: Remove Concepts and Domain (Migrations & Schemas)

**Goal**: Clean up data model by removing concepts and domain.

**Tasks**:
1. Modify `create_diagrams.exs` migration
   - Remove concept_id FK
   - Remove domain field
   - Add GIN index on tags

2. Delete `create_concepts.exs` migration file

3. Update Diagram schema
   - Remove belongs_to :concept
   - Remove field :domain
   - Update changeset

4. Delete Concept schema file

5. Update User schema
   - Remove has_many :owned_concepts

6. Run `mix ecto.reset` to apply changes

**Verification**:
```bash
mix ecto.reset
mix test
```

Existing tests will fail (expected - we removed concepts).

### Phase 2: Create Saved Filters Table

**Goal**: Add saved_filters table and schema.

**Tasks**:
1. Create `create_saved_filters.exs` migration

2. Create SavedFilter schema

3. Update User schema
   - Add has_many :saved_filters

4. Run `mix ecto.reset`

**Verification**:
```bash
mix ecto.reset
```

Schema compiles without warnings.

### Phase 3: Tag Management Functions

**Goal**: Implement tag CRUD and query functions.

**Tasks**:
1. Add tag management functions to Diagrams context
   - `list_available_tags/1`
   - `get_tag_counts/1`
   - `add_tags/3`
   - `remove_tags/3`

2. Write tests for tag functions

3. Remove all concept-related functions from context

**Verification**:
```bash
mix test test/diagram_forge/diagrams_test.exs -t tags
```

### Phase 4: Saved Filter Functions

**Goal**: Implement saved filter CRUD operations.

**Tasks**:
1. Add saved filter functions to Diagrams context
   - `list_saved_filters/1`
   - `list_pinned_filters/1`
   - `create_saved_filter/2`
   - `update_saved_filter/3`
   - `delete_saved_filter/2`
   - `reorder_saved_filters/2`

2. Add tag-based query functions
   - `list_diagrams_by_tags/3`
   - `list_diagrams_by_saved_filter/2`
   - `get_saved_filter_count/2`

3. Write tests for saved filter functions

**Verification**:
```bash
mix test test/diagram_forge/diagrams_test.exs -t filters
```

### Phase 5: Update Fork and Bookmark

**Goal**: Remove concept selection from fork/bookmark flows.

**Tasks**:
1. Update `fork_diagram/2` to remove concept_id parameter
   - Copy tags from original

2. Update `bookmark_diagram/2` to remove concept_id parameter

3. Write tests for updated functions

**Verification**:
```bash
mix test test/diagram_forge/diagrams_test.exs -t fork
mix test test/diagram_forge/diagrams_test.exs -t bookmark
```

### Phase 6: LiveView - Tag Filtering UI

**Goal**: Add tag filtering to sidebar.

**Tasks**:
1. Update mount function in `diagram_studio_live.ex`
   - Add active_tag_filter assign
   - Add available_tags assign
   - Add tag_counts assign

2. Update load_diagrams function
   - Use tag-based queries

3. Add load_tags function

4. Implement tag filtering event handlers
   - `add_tag_to_filter`
   - `remove_tag_from_filter`
   - `clear_filter`

5. Create tag UI components
   - `tag_input_with_autocomplete/1`
   - `active_filter_chips/1`
   - `tag_cloud/1`

6. Update sidebar template
   - Add tag input
   - Show active filter chips
   - Show tag cloud

**Verification**:
```bash
mix test test/diagram_forge_web/live/diagram_studio_live_test.exs -t tags
```

### Phase 7: LiveView - Saved Filters UI

**Goal**: Add saved filter management to sidebar.

**Tasks**:
1. Add load_filters function

2. Implement saved filter event handlers
   - `apply_saved_filter`
   - `show_save_filter_modal`
   - `save_current_filter`
   - `edit_filter`
   - `save_filter_edit`
   - `delete_filter`
   - `toggle_filter_pin`
   - `reorder_filters`

3. Create saved filter components
   - `saved_filter_item/1`
   - `save_filter_modal/1`

4. Update sidebar template
   - Show pinned filters section
   - Add save current filter button
   - Add reorder drag handles

**Verification**:
```bash
mix test test/diagram_forge_web/live/diagram_studio_live_test.exs -t filters
```

### Phase 8: LiveView - Tag Management on Diagrams

**Goal**: Add UI for adding/removing tags on individual diagrams.

**Tasks**:
1. Implement tag management event handlers
   - `add_tags_to_diagram`
   - `remove_tag_from_diagram`

2. Update diagram components
   - `diagram_item_with_tags/1`
   - Show tags on diagram cards
   - Add/remove tag buttons

3. Update diagram edit modal
   - Add tag input field

**Verification**:
```bash
mix test test/diagram_forge_web/live/diagram_studio_live_test.exs -t diagram_tags
```

### Phase 9: Remove Concept UI

**Goal**: Remove all concept-related UI elements.

**Tasks**:
1. Remove concept selection from all forms
   - Diagram create/edit forms
   - Fork modal
   - Bookmark modal

2. Remove concept management UI
   - No more edit/delete concept buttons
   - No more concept grouping in sidebar

3. Update all templates to remove concept references

**Verification**:
Manual testing - verify no concept UI remains.

### Phase 10: Final Tests & Integration

**Goal**: Comprehensive test coverage and integration testing.

**Tasks**:
1. Write integration tests
   - Complete tag filtering flow
   - Save filter → apply filter → edit filter → delete
   - Add tags to diagram → filter by tags
   - Fork with tags → edit tags on fork

2. Update fixtures
   - `saved_filter_fixture/1`
   - `diagram_with_tags_fixture/1`

3. Fix any failing tests

4. Run full test suite
   ```bash
   mix test
   ```

5. Manual testing checklist
   - [ ] Add tags to diagram
   - [ ] Remove tags from diagram
   - [ ] Filter diagrams by tags
   - [ ] Save current filter
   - [ ] Apply saved filter
   - [ ] Edit saved filter
   - [ ] Delete saved filter
   - [ ] Pin/unpin filter
   - [ ] Reorder filters
   - [ ] Fork diagram (tags copied)
   - [ ] Bookmark diagram
   - [ ] Tag autocomplete works
   - [ ] Tag cloud shows counts
   - [ ] No concept UI visible

**Verification**:
```bash
mix test
mix dialyzer
mix credo
mix precommit
```

---

## Files to Create/Modify Summary

### New Files
```
priv/repo/migrations/NNNNNNNNNNNNNN_create_saved_filters.exs
lib/diagram_forge/diagrams/saved_filter.ex
test/diagram_forge/diagrams/saved_filter_test.exs
```

### Files to Modify
```
# Migrations (MODIFY, don't create new)
priv/repo/migrations/20251121181621_create_diagrams.exs

# Schemas
lib/diagram_forge/diagrams/diagram.ex
lib/diagram_forge/accounts/user.ex

# Context
lib/diagram_forge/diagrams.ex

# LiveViews
lib/diagram_forge_web/live/diagram_studio_live.ex

# Tests
test/diagram_forge/diagrams_test.exs
test/diagram_forge_web/live/diagram_studio_live_test.exs
test/support/fixtures/diagrams_fixtures.ex
```

### Files to Delete
```
priv/repo/migrations/20251121181613_create_concepts.exs
lib/diagram_forge/diagrams/concept.ex
test/diagram_forge/diagrams/concept_test.exs (if exists)
```

---

## Success Criteria

Implementation is complete when:
- ✅ Concepts table deleted
- ✅ Domain field removed from diagrams
- ✅ saved_filters table created
- ✅ SavedFilter schema works
- ✅ Tag management functions work
- ✅ Saved filter CRUD works
- ✅ Tag-based queries work correctly
- ✅ Fork copies tags
- ✅ Bookmark works without concepts
- ✅ Tag filtering UI works
- ✅ Saved filters UI works
- ✅ Pin/unpin filters works
- ✅ Reorder filters works
- ✅ Tag autocomplete works
- ✅ Tag cloud shows counts
- ✅ No concept UI visible anywhere
- ✅ All tests pass
- ✅ No Dialyzer warnings
- ✅ No Credo warnings

---

## Performance Considerations

### Indexes Required
All covered in migrations:
- `diagrams(tags)` using GIN - efficient array queries
- `saved_filters(user_id)` - user's filters
- `saved_filters(user_id, is_pinned)` - pinned filters
- `saved_filters(user_id, sort_order)` - ordered filters
- `saved_filters(user_id, name)` - unique filter names

### Query Optimization
- GIN index on tags enables efficient `tag IN tags_array` queries
- Tag filtering uses array contains operator (`@>`)
- Saved filters load once on mount, cached in assigns
- Tag counts computed once, cached until diagrams change

### Potential Bottlenecks
- Tag autocomplete could be slow with 1000s of unique tags
  - Consider caching tag list
  - Consider limiting autocomplete to top N most-used tags
- Filtering by many tags requires multiple array contains checks
  - GIN index should handle this efficiently
  - Monitor query performance with EXPLAIN ANALYZE

---

## Migration Execution Checklist

Before running migrations:
- [ ] Backup any existing data (if applicable)
- [ ] Review all migration changes
- [ ] Ensure indexes are on correct columns
- [ ] Verify foreign keys reference correct tables

Run migrations:
```bash
mix ecto.reset  # Drop, create, migrate, seed
```

After migrations:
- [ ] Verify schema with psql or similar
- [ ] Run test suite
- [ ] Manually test basic flows

---

## End of Implementation Document

This document should be treated as a living document. Update it as implementation progresses, challenges are discovered, or requirements change.

**Next Steps**:
1. Review this document
2. Begin Phase 1 implementation
3. Track progress through phases
4. Update document with learnings
