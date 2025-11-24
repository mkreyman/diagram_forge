# DiagramForge Ownership and Visibility Implementation Guide

## Overview

This document provides a comprehensive implementation plan for adding ownership, visibility controls, and collaborative features to DiagramForge. The redesign transforms DiagramForge from a simple diagram viewer into a collaborative platform with proper access control, fork/save functionality, and public discovery.

## Current State Analysis

### Existing Structure
- **Users**: Authenticate via GitHub OAuth
- **Diagrams**: Have `user_id` (owner) field and `tags` array for organization
- **Saved Filters**: (From tags migration) User-defined tag combinations for quick filtering
- **Visibility**: No controls - all diagrams accessible via permalink
- **UI**: No edit/delete functionality for diagrams
- **Collaboration**: No fork/save/bookmark features

### Current Files
```
lib/diagram_forge/
├── diagrams.ex                  # Context with CRUD operations
├── diagrams/
│   ├── diagram.ex              # Schema with user_id and tags
│   ├── saved_filter.ex         # Tag-based filters for organization
│   └── document.ex
├── accounts/
│   └── user.ex                 # Has many diagrams
priv/repo/migrations/
├── 20251121181621_create_diagrams.exs
├── NNNNNNNNNNNNNN_create_saved_filters.exs
├── 20251122192520_create_users.exs
└── 20251122192602_add_user_id_to_diagrams.exs
```

---

## Data Model Changes

### 1. Remove Direct Diagram Ownership

**Current**: `diagrams.user_id` establishes ownership directly

**New**: Use join table for many-to-many relationship (users can own, fork, or bookmark diagrams)

### 2. Create `user_diagrams` Join Table

This table tracks the relationship between users and diagrams, including ownership status.

**Fields:**
- `user_id` (binary_id, FK to users, not null)
- `diagram_id` (binary_id, FK to diagrams, not null)
- `is_owner` (boolean, not null, default: false)
- `inserted_at` (timestamp)
- `updated_at` (timestamp)

**Constraints:**
- Primary key: `[user_id, diagram_id]`
- Index on `user_id` for efficient "my diagrams" queries
- Index on `diagram_id` for efficient ownership checks
- Index on `[user_id, is_owner]` for filtering owned vs bookmarked

**Semantics:**
- `is_owner: true` - User created or forked this diagram (can edit/delete)
- `is_owner: false` - User bookmarked/saved this diagram (read-only)
- No entry - User has no relationship with this diagram

### 3. Tags and Saved Filters (No Changes Needed)

**Note**: Tags and saved_filters already implemented in previous migration.

**Organization Model:**
- Diagrams organized via tags (array field)
- Users create saved_filters (named tag combinations)
- No concept table - tags provide flexible categorization

### 4. Add Diagram Visibility

**New Field**: `diagrams.visibility` (enum)

**Values:**
- `:private` - Only owner can view (even via permalink)
- `:unlisted` - Anyone with link can view (default)
- `:public` - Anyone can view + discoverable in public feed

**Default**: `:unlisted` (backward compatible - maintains current behavior)

### 5. Add Fork Tracking

**New Field**: `diagrams.forked_from_id` (binary_id, FK to diagrams, nullable)

**Purpose:**
- Track fork lineage
- Could enable "view original" functionality
- Analytics on popular diagrams (most forked)

### 6. Add User Preferences

**New Field**: `users.show_public_diagrams` (boolean, default: false)

**Purpose:**
- User preference for showing public diagrams in sidebar
- Persisted across sessions
- Allows users to opt-in to discovery

---

## Migration Strategy

### Philosophy: Modify Existing Migrations

Since this is early development:
1. MODIFY existing migration files (don't create new ones)
2. User will run `mix ecto.reset` in dev and test
3. Cleaner migration history
4. No production data to preserve

### Migration Changes Required

#### File: `priv/repo/migrations/20251121181621_create_diagrams.exs`

**Changes:**
1. Remove `user_id` field (will be in join table)
2. Remove `created_by_superadmin` field (no longer needed with new model)
3. Add `visibility` field (enum: private, unlisted, public)
4. Add `forked_from_id` field (self-referential FK)

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
    create index(:diagrams, [:tags], using: :gin)
  end
end
```

#### File: `priv/repo/migrations/20251122192602_add_user_id_to_diagrams.exs`

**Changes:**
1. DELETE this file entirely (we're using join table instead)

#### File: `priv/repo/migrations/NNNNNNNNNNNNNN_create_saved_filters.exs`

**Note:** This was already created in the tags migration.

**No Changes Needed** - saved_filters table exists from previous migration.

#### File: `priv/repo/migrations/20251122192520_create_users.exs`

**Changes:**
1. Add `show_public_diagrams` preference field

```elixir
defmodule DiagramForge.Repo.Migrations.CreateUsers do
  use Ecto.Migration

  def change do
    create table(:users, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :email, :string, null: false
      add :name, :string
      add :provider, :string, default: "github", null: false
      add :provider_uid, :string, null: false
      add :provider_token, :binary
      add :avatar_url, :string
      add :last_sign_in_at, :utc_datetime
      add :show_public_diagrams, :boolean, default: false, null: false

      timestamps()
    end

    create unique_index(:users, [:email])
    create unique_index(:users, [:provider, :provider_uid])
  end
end
```

#### New File: `priv/repo/migrations/NNNNNNNNNNNNNN_create_user_diagrams.exs`

**Purpose:** Create many-to-many join table

```elixir
defmodule DiagramForge.Repo.Migrations.CreateUserDiagrams do
  use Ecto.Migration

  def change do
    create table(:user_diagrams, primary_key: false) do
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all),
        null: false
      add :diagram_id, references(:diagrams, type: :binary_id, on_delete: :delete_all),
        null: false
      add :is_owner, :boolean, null: false, default: false

      timestamps()
    end

    # Composite primary key ensures one entry per user-diagram pair
    create unique_index(:user_diagrams, [:user_id, :diagram_id])

    # Efficient queries for "my diagrams"
    create index(:user_diagrams, [:user_id])

    # Efficient ownership checks
    create index(:user_diagrams, [:diagram_id])

    # Filter owned vs bookmarked
    create index(:user_diagrams, [:user_id, :is_owner])
  end
end
```

**Migration Order:**
1. Create users table (already exists)
2. Create diagrams table (modify existing - remove user_id, add visibility + forked_from_id)
3. Create concepts table (modify existing - add owner_id)
4. Create user_diagrams join table (new migration)

---

## Schema Changes

### 1. Update `lib/diagram_forge/diagrams/diagram.ex`

**Changes:**
- Remove `belongs_to :user` (replaced by many_to_many)
- Add `many_to_many :users` through join table
- Add `visibility` enum field
- Add `forked_from_id` for fork tracking
- Remove `created_by_superadmin` field
- Update changeset

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

### 2. Create `lib/diagram_forge/diagrams/saved_filter.ex`

**Note**: Already created in tags migration. Saved filters allow users to save tag combinations as named filters.

### 3. Create `lib/diagram_forge/diagrams/user_diagram.ex`

**New Schema:** Join table for many-to-many relationship

```elixir
defmodule DiagramForge.Diagrams.UserDiagram do
  @moduledoc """
  Join table tracking user-diagram relationships.

  ## Relationship Types

  - `is_owner: true` - User created or forked this diagram (can edit/delete)
  - `is_owner: false` - User bookmarked/saved this diagram (read-only)
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false
  @foreign_key_type :binary_id

  schema "user_diagrams" do
    belongs_to :user, DiagramForge.Accounts.User
    belongs_to :diagram, DiagramForge.Diagrams.Diagram

    field :is_owner, :boolean, default: false

    timestamps()
  end

  def changeset(user_diagram, attrs) do
    user_diagram
    |> cast(attrs, [:user_id, :diagram_id, :is_owner])
    |> validate_required([:user_id, :diagram_id, :is_owner])
    |> unique_constraint([:user_id, :diagram_id])
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:diagram_id)
  end
end
```

### 4. Delete `lib/diagram_forge/diagrams/concept.ex`

**Action**: Delete this file entirely. Concepts removed in tags migration.

### 5. Update `lib/diagram_forge/accounts/user.ex`

**Changes:**
- Remove simple `has_many :diagrams` (replaced by many_to_many)
- Add `many_to_many :diagrams` through join table
- Add `has_many :saved_filters` (from tags migration)
- Add `show_public_diagrams` preference field

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

### New Authorization Functions

```elixir
@doc """
Checks if a user owns a diagram.
"""
def user_owns_diagram?(diagram_id, user_id) do
  Repo.exists?(
    from ud in UserDiagram,
      where: ud.diagram_id == ^diagram_id
        and ud.user_id == ^user_id
        and ud.is_owner == true
  )
end

@doc """
Checks if a user has bookmarked a diagram.
"""
def user_bookmarked_diagram?(diagram_id, user_id) do
  Repo.exists?(
    from ud in UserDiagram,
      where: ud.diagram_id == ^diagram_id
        and ud.user_id == ^user_id
        and ud.is_owner == false
  )
end

@doc """
Gets the owner of a diagram (first user with is_owner: true).
Returns nil if no owner exists.
"""
def get_diagram_owner(diagram_id) do
  Repo.one(
    from u in User,
      join: ud in UserDiagram,
      on: ud.user_id == u.id,
      where: ud.diagram_id == ^diagram_id and ud.is_owner == true,
      limit: 1
  )
end

@doc """
Checks if a user can view a diagram based on visibility rules.

- Private: Only owner can view
- Unlisted: Anyone can view
- Public: Anyone can view
"""
def can_view_diagram?(%Diagram{} = diagram, user) do
  case diagram.visibility do
    :private -> user && user_owns_diagram?(diagram.id, user.id)
    :unlisted -> true
    :public -> true
  end
end

@doc """
Checks if a user can edit a diagram (must be owner).
"""
def can_edit_diagram?(%Diagram{} = diagram, user) do
  user && user_owns_diagram?(diagram.id, user.id)
end

@doc """
Checks if a user can delete a diagram (must be owner).
"""
def can_delete_diagram?(%Diagram{} = diagram, user) do
  user && user_owns_diagram?(diagram.id, user.id)
end

```

### Diagram Listing Functions

```elixir
@doc """
Lists diagrams owned by a user (is_owner: true).
"""
def list_owned_diagrams(user_id) do
  Repo.all(
    from d in Diagram,
      join: ud in UserDiagram,
      on: ud.diagram_id == d.id,
      where: ud.user_id == ^user_id and ud.is_owner == true,
      order_by: [desc: d.inserted_at],
      preload: [:concept]
  )
end

@doc """
Lists diagrams bookmarked by a user (is_owner: false).
"""
def list_bookmarked_diagrams(user_id) do
  Repo.all(
    from d in Diagram,
      join: ud in UserDiagram,
      on: ud.diagram_id == d.id,
      where: ud.user_id == ^user_id and ud.is_owner == false,
      order_by: [desc: d.inserted_at],
      preload: [:concept]
  )
end

@doc """
Lists all public diagrams for discovery feed.
"""
def list_public_diagrams do
  Repo.all(
    from d in Diagram,
      where: d.visibility == :public,
      order_by: [desc: d.inserted_at],
      preload: [:concept]
  )
end

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
```

### CRUD Operations

```elixir
@doc """
Creates a diagram with user ownership.

Creates both the diagram and the user_diagrams entry with is_owner: true.
"""
def create_diagram_for_user(attrs, user_id) do
  Repo.transaction(fn ->
    # Create diagram
    diagram_changeset = Diagram.changeset(%Diagram{}, attrs)

    case Repo.insert(diagram_changeset) do
      {:ok, diagram} ->
        # Create ownership entry
        user_diagram_changeset =
          UserDiagram.changeset(%UserDiagram{}, %{
            user_id: user_id,
            diagram_id: diagram.id,
            is_owner: true
          })

        case Repo.insert(user_diagram_changeset) do
          {:ok, _user_diagram} -> diagram
          {:error, changeset} -> Repo.rollback(changeset)
        end

      {:error, changeset} ->
        Repo.rollback(changeset)
    end
  end)
end

@doc """
Updates a diagram (only owner can update).
"""
def update_diagram(%Diagram{} = diagram, attrs, user_id) do
  if can_edit_diagram?(diagram, %{id: user_id}) do
    diagram
    |> Diagram.changeset(attrs)
    |> Repo.update()
  else
    {:error, :unauthorized}
  end
end

@doc """
Deletes a diagram (only owner can delete).

Cascades to user_diagrams automatically.
"""
def delete_diagram(%Diagram{} = diagram, user_id) do
  if can_delete_diagram?(diagram, %{id: user_id}) do
    Repo.delete(diagram)
  else
    {:error, :unauthorized}
  end
end

@doc """
Removes a diagram bookmark (removes user_diagrams entry with is_owner: false).
"""
def remove_diagram_bookmark(diagram_id, user_id) do
  Repo.delete_all(
    from ud in UserDiagram,
      where: ud.diagram_id == ^diagram_id
        and ud.user_id == ^user_id
        and ud.is_owner == false
  )

  :ok
end

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
      visibility: :unlisted,  # Forked diagrams default to unlisted
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

# Helper function for generating unique slugs
defp generate_unique_slug(base_slug) do
  # Add timestamp or random suffix to ensure uniqueness
  suffix = :crypto.strong_rand_bytes(4) |> Base.encode16(case: :lower)
  "#{base_slug}-#{suffix}"
end
```

### User Preferences

```elixir
@doc """
Updates user's show_public_diagrams preference.
"""
def update_user_public_diagrams_preference(user, show_public) do
  user
  |> User.preferences_changeset(%{show_public_diagrams: show_public})
  |> Repo.update()
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

[List of diagrams matching current filter]
├─ Diagram 1 [elixir, oauth]
├─ Diagram 2 [elixir, patterns]
└─ Diagram 3 [oauth, security]

FORKED DIAGRAMS (4)
[Similar structure with tag filter]

──────────────
☐ Show All Public Diagrams
```

### Main LiveView: `lib/diagram_forge_web/live/diagram_studio_live.ex`

**Key Changes:**
1. Load owned diagrams separately from bookmarked
2. Handle public diagrams toggle
3. Group diagrams by concept with ownership flag
4. Handle edit/delete/fork/save events
5. Show appropriate UI based on ownership

**Mount Function:**
```elixir
def mount(_params, _session, socket) do
  current_user = socket.assigns[:current_user]

  socket =
    socket
    |> assign(:current_user, current_user)
    |> load_diagrams()
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
```

**Event Handlers:**
```elixir
def handle_event("toggle_public_diagrams", %{"value" => value}, socket) do
  show_public = value == "true"

  socket =
    socket
    |> assign(:show_public_diagrams, show_public)
    |> load_diagrams()

  # Persist preference
  if socket.assigns.current_user do
    Diagrams.update_user_public_diagrams_preference(
      socket.assigns.current_user,
      show_public
    )
  end

  {:noreply, socket}
end

def handle_event("edit_diagram", %{"id" => id}, socket) do
  diagram = Diagrams.get_diagram!(id)

  if Diagrams.can_edit_diagram?(diagram, socket.assigns.current_user) do
    {:noreply, assign(socket, :editing_diagram, diagram)}
  else
    {:noreply, put_flash(socket, :error, "You don't have permission to edit this diagram")}
  end
end

def handle_event("save_diagram_edit", %{"diagram" => params}, socket) do
  diagram = socket.assigns.editing_diagram
  user_id = socket.assigns.current_user.id

  case Diagrams.update_diagram(diagram, params, user_id) do
    {:ok, _updated} ->
      socket =
        socket
        |> assign(:editing_diagram, nil)
        |> load_diagrams()
        |> put_flash(:info, "Diagram updated successfully")

      {:noreply, socket}

    {:error, %Ecto.Changeset{} = changeset} ->
      {:noreply, assign(socket, :diagram_changeset, changeset)}

    {:error, :unauthorized} ->
      {:noreply, put_flash(socket, :error, "Unauthorized")}
  end
end

def handle_event("delete_diagram", %{"id" => id}, socket) do
  diagram = Diagrams.get_diagram!(id)
  user_id = socket.assigns.current_user.id

  case Diagrams.delete_diagram(diagram, user_id) do
    {:ok, _} ->
      socket =
        socket
        |> load_diagrams()
        |> put_flash(:info, "Diagram deleted successfully")

      {:noreply, socket}

    {:error, :unauthorized} ->
      {:noreply, put_flash(socket, :error, "Unauthorized")}
  end
end

def handle_event("remove_bookmark", %{"id" => id}, socket) do
  user_id = socket.assigns.current_user.id

  :ok = Diagrams.remove_diagram_bookmark(id, user_id)

  socket =
    socket
    |> load_diagrams()
    |> put_flash(:info, "Diagram removed from your collection")

  {:noreply, socket}
end

def handle_event("fork_diagram", %{"id" => id}, socket) do
  user_id = socket.assigns.current_user.id

  case Diagrams.fork_diagram(id, user_id) do
    {:ok, _forked} ->
      socket =
        socket
        |> load_diagrams()
        |> put_flash(:info, "Diagram forked successfully - tags copied from original")

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
        |> put_flash(:info, "Diagram bookmarked successfully - add your own tags to organize")

      {:noreply, socket}

    {:error, _reason} ->
      {:noreply, put_flash(socket, :error, "Failed to bookmark diagram")}
  end
end

def handle_event("change_visibility", %{"id" => id, "visibility" => visibility}, socket) do
  diagram = Diagrams.get_diagram!(id)
  user_id = socket.assigns.current_user.id
  visibility_atom = String.to_existing_atom(visibility)

  case Diagrams.update_diagram(diagram, %{visibility: visibility_atom}, user_id) do
    {:ok, _updated} ->
      socket =
        socket
        |> load_diagrams()
        |> put_flash(:info, "Visibility updated to #{visibility}")

      {:noreply, socket}

    {:error, :unauthorized} ->
      {:noreply, put_flash(socket, :error, "Unauthorized")}
  end
end
```

### Permalink View: Update to Check Visibility

**File:** `lib/diagram_forge_web/live/diagram_view_live.ex` (or similar)

```elixir
def mount(%{"id" => id}, _session, socket) do
  diagram = Diagrams.get_diagram!(id)
  current_user = socket.assigns[:current_user]

  if Diagrams.can_view_diagram?(diagram, current_user) do
    socket =
      socket
      |> assign(:diagram, diagram)
      |> assign(:is_owner, Diagrams.can_edit_diagram?(diagram, current_user))

    {:ok, socket}
  else
    socket =
      socket
      |> put_flash(:error, "This diagram is private")
      |> redirect(to: ~p"/")

    {:ok, socket}
  end
end
```

---

## UI Components

### Edit Diagram Modal

**Component:** Core component for editing diagram

```elixir
attr :diagram, :map, required: true
attr :on_save, :string, required: true
attr :on_cancel, :string, required: true

def edit_diagram_modal(assigns) do
  ~H"""
  <div class="fixed inset-0 bg-black bg-opacity-50 flex items-center justify-center z-50">
    <div class="bg-white rounded-lg p-6 max-w-4xl w-full max-h-[90vh] overflow-y-auto">
      <h2 class="text-2xl font-bold mb-4">Edit Diagram</h2>

      <.form for={@form} id="edit-diagram-form" phx-submit={@on_save}>
        <div class="space-y-4">
          <.input field={@form[:title]} type="text" label="Title" required />

          <.input
            field={@form[:diagram_source]}
            type="textarea"
            label="Mermaid Source"
            required
            rows={15}
            class="font-mono text-sm"
          />

          <.input field={@form[:summary]} type="textarea" label="Summary" rows={3} />

          <.input field={@form[:notes_md]} type="textarea" label="Notes (Markdown)" rows={5} />

          <.input
            field={@form[:tags]}
            type="text"
            label="Tags (comma-separated)"
          />

          <.input
            field={@form[:visibility]}
            type="select"
            label="Visibility"
            options={[
              {"Private (only you)", "private"},
              {"Unlisted (anyone with link)", "unlisted"},
              {"Public (discoverable)", "public"}
            ]}
          />

          <.input
            field={@form[:tags]}
            type="text"
            label="Tags (comma-separated)"
            placeholder="elixir, oauth, patterns"
          />
        </div>

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
            Save Changes
          </button>
        </div>
      </.form>
    </div>
  </div>
  """
end
```

### Tag Management Components

**Note**: Tag input, filter chips, and tag cloud components defined in tags migration document.

Fork and bookmark operations now happen immediately without concept selection modals.

### Saved Filter Item (Sidebar)

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

### Visibility Banner (on diagram view)

```elixir
attr :diagram, :map, required: true
attr :is_owner, :boolean, default: false

def visibility_banner(assigns) do
  ~H"""
  <div class={[
    "px-4 py-2 rounded-lg mb-4 flex items-center justify-between",
    visibility_class(@diagram.visibility)
  ]}>
    <div class="flex items-center gap-2">
      <.icon name={visibility_icon(@diagram.visibility)} class="w-5 h-5" />
      <span class="font-medium">
        {visibility_label(@diagram.visibility)}
      </span>
    </div>

    <%= if @is_owner do %>
      <select
        phx-change="change_visibility"
        phx-value-id={@diagram.id}
        class="bg-transparent border-gray-300 rounded"
      >
        <option value="private" selected={@diagram.visibility == :private}>
          Private
        </option>
        <option value="unlisted" selected={@diagram.visibility == :unlisted}>
          Unlisted
        </option>
        <option value="public" selected={@diagram.visibility == :public}>
          Public
        </option>
      </select>
    <% end %>
  </div>
  """
end

defp visibility_class(:private), do: "bg-red-100 text-red-800"
defp visibility_class(:unlisted), do: "bg-yellow-100 text-yellow-800"
defp visibility_class(:public), do: "bg-green-100 text-green-800"

defp visibility_icon(:private), do: "hero-lock-closed"
defp visibility_icon(:unlisted), do: "hero-link"
defp visibility_icon(:public), do: "hero-globe-alt"

defp visibility_label(:private), do: "Private - Only you can view"
defp visibility_label(:unlisted), do: "Unlisted - Anyone with link can view"
defp visibility_label(:public), do: "Public - Discoverable by everyone"
```

### Public Diagrams Toggle

```elixir
attr :show_public_diagrams, :boolean, required: true

def public_diagrams_toggle(assigns) do
  ~H"""
  <div class="px-3 py-2 border-t border-gray-200 mt-4">
    <label class="flex items-center gap-2 cursor-pointer">
      <input
        type="checkbox"
        checked={@show_public_diagrams}
        phx-change="toggle_public_diagrams"
        value={to_string(!@show_public_diagrams)}
        class="rounded border-gray-300"
      />
      <span class="text-sm">Show All Public Diagrams</span>
    </label>
  </div>
  """
end
```

---

## Test Coverage

### Test Files to Create/Modify

#### 1. `test/diagram_forge/diagrams_test.exs`

**Test Cases:**
- Authorization functions
  - `user_owns_diagram?/2`
  - `user_bookmarked_diagram?/2`
  - `can_view_diagram?/2` with different visibility levels
  - `can_edit_diagram?/2`
  - `can_delete_diagram?/2`
  - `user_owns_concept?/2`
  - `can_delete_concept?/2` (empty vs non-empty)

- CRUD operations
  - `create_diagram_for_user/2` creates diagram + user_diagrams entry
  - `update_diagram/3` only allows owner to update
  - `delete_diagram/2` only allows owner to delete
  - `remove_diagram_bookmark/2` removes bookmark entry
  - `fork_diagram/3` creates new diagram with forked_from_id
  - `bookmark_diagram/3` creates bookmark entry
  - `create_concept_for_user/2`
  - `update_concept/3` only allows owner
  - `delete_concept/2` only allows owner of empty concept

- Query functions
  - `list_owned_diagrams/1` returns only is_owner: true
  - `list_bookmarked_diagrams/1` returns only is_owner: false
  - `list_public_diagrams/0` returns only public visibility
  - `list_owned_concepts/1`
  - `group_diagrams_by_concept/2`

#### 2. `test/diagram_forge_web/live/diagram_studio_live_test.exs`

**Test Cases:**
- Mount loads correct data for user
- Toggle public diagrams updates preference and reloads
- Edit diagram modal appears for owner
- Edit diagram saves changes
- Edit diagram unauthorized for non-owner
- Delete diagram removes it
- Delete diagram unauthorized for non-owner
- Remove bookmark removes entry
- Fork diagram creates new diagram with new owner
- Bookmark diagram creates bookmark entry
- Edit concept renames it
- Edit concept unauthorized for non-owner
- Delete concept removes empty concept
- Delete concept fails for non-empty concept
- Visibility change updates diagram

#### 3. `test/diagram_forge_web/live/diagram_view_live_test.exs`

**Test Cases:**
- Private diagram blocks non-owner
- Private diagram allows owner
- Unlisted diagram allows anyone with link
- Public diagram allows anyone
- Owner sees edit controls
- Non-owner doesn't see edit controls
- Visibility banner shows correct state
- Owner can change visibility

#### 4. `test/diagram_forge/diagrams/user_diagram_test.exs`

**Test Cases:**
- Changeset validation
- Unique constraint on [user_id, diagram_id]
- Foreign key constraints

#### 5. `test/diagram_forge/diagrams/saved_filter_test.exs`

**Test Cases:**
- Changeset validation
- Unique constraint on [user_id, name]
- Foreign key constraints
- Tag filter queries work correctly

#### 6. `test/support/fixtures/diagrams_fixtures.ex`

**Add Fixtures:**
```elixir
def user_diagram_fixture(attrs \\ %{}) do
  user = attrs[:user] || DiagramForge.AccountsFixtures.user_fixture()
  diagram = attrs[:diagram] || diagram_fixture()

  {:ok, user_diagram} =
    %DiagramForge.Diagrams.UserDiagram{}
    |> DiagramForge.Diagrams.UserDiagram.changeset(
      Enum.into(attrs, %{
        user_id: user.id,
        diagram_id: diagram.id,
        is_owner: true
      })
    )
    |> DiagramForge.Repo.insert()

  user_diagram
end

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
  attrs =
    attrs
    |> Map.put_new(:tags, ["elixir", "phoenix", "test"])

  diagram_fixture(attrs)
end
```

---

## Implementation Phases

### Phase 1: Data Model (Migrations & Schemas)

**Goal:** Update database schema and Ecto schemas

**Tasks:**
1. Modify `create_diagrams.exs` migration
   - Remove user_id field
   - Remove created_by_superadmin field
   - Add visibility enum field
   - Add forked_from_id field

2. Delete `add_user_id_to_diagrams.exs` migration

3. Modify `create_users.exs` migration
   - Add show_public_diagrams field

4. Create new `create_user_diagrams.exs` migration
   - Create join table with proper indexes

5. Update Diagram schema
   - Remove belongs_to :user
   - Add many_to_many :users
   - Add belongs_to :forked_from
   - Add visibility enum field
   - Keep tags field (from tags migration)
   - Remove created_by_superadmin field

6. Create UserDiagram schema
   - Define join table schema

7. Update User schema
   - Replace has_many :diagrams with many_to_many
   - Add has_many :saved_filters (from tags migration)
   - Add show_public_diagrams field
   - Add preferences_changeset

**Verification:**
```bash
mix ecto.reset
mix test
```

All existing tests should fail (expected - we changed the data model).

### Phase 2: Core Context Functions

**Goal:** Implement authorization and CRUD functions

**Tasks:**
1. Add authorization functions to Diagrams context
   - `user_owns_diagram?/2`
   - `user_bookmarked_diagram?/2`
   - `get_diagram_owner/1`
   - `can_view_diagram?/2`
   - `can_edit_diagram?/2`
   - `can_delete_diagram?/2`
   - `user_owns_concept?/2`
   - `can_delete_concept?/2`

2. Add query functions
   - `list_owned_diagrams/1`
   - `list_bookmarked_diagrams/1`
   - `list_public_diagrams/0`
   - `list_diagrams_by_tags/3` (from tags migration)

3. Update CRUD functions
   - `create_diagram_for_user/2` (with transaction)
   - `update_diagram/3` (with auth check)
   - `delete_diagram/2` (with auth check)

4. Add user preferences function
   - `update_user_public_diagrams_preference/2`

5. Remove old functions that reference concepts
   - Delete `list_owned_concepts/1`
   - Delete `group_diagrams_by_concept/2`
   - Delete `user_owns_concept?/2`
   - Delete `can_delete_concept?/2`
   - Delete `create_concept_for_user/2`
   - Delete `update_concept/3`
   - Delete `delete_concept/2`

**Verification:**
```bash
mix test test/diagram_forge/diagrams_test.exs
```

Write tests first, then implement functions until tests pass.

### Phase 3: Fork & Save Functionality

**Goal:** Implement fork and bookmark features (without concept selection)

**Tasks:**
1. Implement `fork_diagram/2` (removed concept_id parameter)
   - Create new diagram with copied data
   - Copy tags from original
   - Set forked_from_id
   - Create user_diagrams entry with is_owner: true
   - Generate unique slug

2. Implement `bookmark_diagram/2` (removed concept_id parameter)
   - Create user_diagrams entry with is_owner: false
   - User can add their own tags after bookmarking

3. Implement `remove_diagram_bookmark/2`
   - Remove user_diagrams entry

4. Add helper function `generate_unique_slug/1`

5. Write tests for fork/save flows

**Verification:**
```bash
mix test test/diagram_forge/diagrams_test.exs -t fork
mix test test/diagram_forge/diagrams_test.exs -t bookmark
```

### Phase 4: LiveView Updates - Sidebar

**Goal:** Update sidebar to show owned, bookmarked, and public diagrams

**Tasks:**
1. Update mount function in `diagram_studio_live.ex`
   - Load owned diagrams (filtered by tags)
   - Load bookmarked diagrams (filtered by tags)
   - Load public diagrams (if preference enabled)
   - Load pinned filters

2. Add `load_diagrams/1` helper function (uses tag filtering)

3. Add `load_tags/1` helper function

4. Add `load_filters/1` helper function

5. Implement event handlers
   - `toggle_public_diagrams`
   - `add_tag_to_filter`
   - `remove_tag_from_filter`
   - `clear_filter`
   - `apply_saved_filter`

6. Update sidebar template
   - Show "MY DIAGRAMS" section with tag filter input
   - Show "PINNED FILTERS" section
   - Show active filter chips
   - Show "FORKED DIAGRAMS" section with tag filter
   - Show "PUBLIC DIAGRAMS" section (conditional)
   - Add public diagrams toggle

7. Create sidebar components
   - `tag_input_with_autocomplete/1`
   - `active_filter_chips/1`
   - `saved_filter_item/1`
   - `diagram_item_with_tags/1`
   - `public_diagrams_toggle/1`

**Verification:**
```bash
mix test test/diagram_forge_web/live/diagram_studio_live_test.exs -t sidebar
```

### Phase 5: LiveView Updates - Diagram Actions

**Goal:** Implement edit, delete, fork, save actions

**Tasks:**
1. Implement event handlers
   - `edit_diagram`
   - `save_diagram_edit`
   - `delete_diagram`
   - `remove_bookmark`
   - `fork_diagram` (no concept selection)
   - `bookmark_diagram` (no concept selection)
   - `change_visibility`
   - `add_tags_to_diagram`
   - `remove_tag_from_diagram`

2. Create modal components
   - `edit_diagram_modal/1` (with tag input instead of concept select)
   - `save_filter_modal/1`

3. Add modal state to socket assigns
   - `:editing_diagram`
   - `:show_save_filter_modal`
   - `:editing_filter`

4. Update diagram view template
   - Add visibility banner
   - Show edit/delete buttons for owner
   - Show fork/save buttons (no modal, immediate action)
   - Show tags on each diagram
   - Add tag management UI

5. Create visibility components
   - `visibility_banner/1`
   - Helper functions for visibility styling

**Verification:**
```bash
mix test test/diagram_forge_web/live/diagram_studio_live_test.exs -t actions
```

### Phase 6: Visibility Controls & Permalink

**Goal:** Implement visibility access control

**Tasks:**
1. Update permalink view (`diagram_view_live.ex` or create it)
   - Check `can_view_diagram?/2` in mount
   - Redirect if unauthorized
   - Show visibility banner
   - Show edit controls if owner
   - Implement visibility change handler

2. Add visibility change event handler
   - Validate user is owner
   - Update diagram visibility
   - Reload diagram

3. Update any diagram creation flows
   - Default visibility to :unlisted
   - Allow specifying visibility

**Verification:**
```bash
mix test test/diagram_forge_web/live/diagram_view_live_test.exs
```

### Phase 7: Final Tests & Integration

**Goal:** Comprehensive test coverage and integration testing

**Tasks:**
1. Write integration tests
   - Complete user flow: create → edit → fork → delete
   - Bookmark flow: find public → bookmark → organize → remove
   - Visibility flow: create private → view denied → make public → view allowed
   - Concept management: create → rename → delete empty → prevent delete non-empty

2. Update fixtures
   - Add `user_diagram_fixture/1`
   - Add `concept_with_owner_fixture/1`
   - Update existing fixtures to work with new model

3. Fix any failing tests from earlier phases

4. Run full test suite
   ```bash
   mix test
   ```

5. Manual testing checklist
   - [ ] Create diagram as authenticated user
   - [ ] Edit own diagram (including tags)
   - [ ] Delete own diagram
   - [ ] Fork someone else's diagram (tags copied)
   - [ ] Bookmark someone else's diagram
   - [ ] Remove bookmark
   - [ ] Add tags to diagram
   - [ ] Remove tags from diagram
   - [ ] Filter diagrams by tags
   - [ ] Save current filter as named filter
   - [ ] Apply saved filter
   - [ ] Edit saved filter
   - [ ] Delete saved filter
   - [ ] Pin/unpin filter
   - [ ] Reorder filters
   - [ ] Change diagram visibility
   - [ ] Access private diagram as non-owner (should fail)
   - [ ] Access unlisted diagram as guest (should work)
   - [ ] Access public diagram as guest (should work)
   - [ ] Toggle public diagrams feed
   - [ ] Verify preference persists across sessions
   - [ ] Tag autocomplete works
   - [ ] Tag cloud shows counts

**Verification:**
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
priv/repo/migrations/NNNNNNNNNNNNNN_create_user_diagrams.exs
lib/diagram_forge/diagrams/user_diagram.ex
test/diagram_forge/diagrams/user_diagram_test.exs
```

### Files Already Created (Tags Migration)
```
priv/repo/migrations/NNNNNNNNNNNNNN_create_saved_filters.exs
lib/diagram_forge/diagrams/saved_filter.ex
test/diagram_forge/diagrams/saved_filter_test.exs
```

### Files to Modify
```
# Migrations (MODIFY, don't create new)
priv/repo/migrations/20251121181621_create_diagrams.exs
priv/repo/migrations/20251122192520_create_users.exs

# Schemas
lib/diagram_forge/diagrams/diagram.ex
lib/diagram_forge/accounts/user.ex

# Context
lib/diagram_forge/diagrams.ex

# LiveViews
lib/diagram_forge_web/live/diagram_studio_live.ex
lib/diagram_forge_web/live/diagram_view_live.ex  # or create if doesn't exist

# Tests
test/diagram_forge/diagrams_test.exs
test/diagram_forge_web/live/diagram_studio_live_test.exs
test/diagram_forge_web/live/diagram_view_live_test.exs  # or create
test/support/fixtures/diagrams_fixtures.ex
```

### Files to Delete
```
priv/repo/migrations/20251122192602_add_user_id_to_diagrams.exs
priv/repo/migrations/20251121181613_create_concepts.exs
lib/diagram_forge/diagrams/concept.ex
test/diagram_forge/diagrams/concept_test.exs (if exists)
```

---

## Rollback Strategy (If Needed)

Since we're modifying migrations and running `mix ecto.reset`:

**In Development:**
- Just restore from git: `git checkout .`
- Drop DB: `mix ecto.drop`
- Recreate: `mix ecto.setup`

**If This Were Production (Future):**
Would need proper up/down migrations:
1. Create `user_diagrams` table
2. Migrate data from `diagrams.user_id` to `user_diagrams` with `is_owner: true`
3. Add new fields to existing tables
4. Safely remove old fields

---

## Performance Considerations

### Indexes Required
All covered in migrations:
- `user_diagrams(user_id)` - "my diagrams" queries
- `user_diagrams(diagram_id)` - ownership checks
- `user_diagrams(user_id, is_owner)` - filter owned vs bookmarked
- `diagrams(visibility)` - public diagrams feed
- `diagrams(forked_from_id)` - fork lineage queries
- `diagrams(tags)` using GIN - efficient tag queries (from tags migration)
- `saved_filters(user_id)` - user's filters (from tags migration)
- `saved_filters(user_id, is_pinned)` - pinned filters (from tags migration)
- `saved_filters(user_id, sort_order)` - ordered filters (from tags migration)

### Query Optimization
- GIN index on tags enables efficient array contains queries
- Tag filtering uses array operators for performance
- Saved filters cached in assigns, reloaded only when needed
- No N+1 queries - tags stored directly on diagram records

### Potential Bottlenecks
- Public diagrams feed could grow large
  - Consider pagination (add in future phase)
  - Consider caching popular public diagrams
- Fork lineage queries (for "view original" feature)
  - Index on forked_from_id handles this
- Tag autocomplete with thousands of unique tags
  - Consider limiting to top N most-used tags
  - Consider caching tag list
- Complex tag filters with many tags
  - GIN index should handle efficiently
  - Monitor with EXPLAIN ANALYZE

---

## Security Considerations

### Authorization Checks
Always check authorization before:
- Viewing private diagrams
- Editing diagrams (must be owner)
- Deleting diagrams (must be owner)
- Managing tags on diagrams (must be owner)
- Editing saved filters (must be owner)
- Deleting saved filters (must be owner)

### Input Validation
- Sanitize Mermaid source (consider validation)
- Validate visibility enum values
- Validate tag format (no special characters, reasonable length)
- Validate saved filter names (unique per user, reasonable length)
- CSRF protection (built-in with Phoenix)

### Privacy
- Private diagrams never exposed via API or sidebar
- Unlisted diagrams require direct link
- Public diagrams opt-in via visibility setting

---

## Future Enhancements (Not in This Phase)

### Phase 8 (Future)
- **Fork lineage visualization**: Show "forked from" link
- **Popular diagrams**: Most forked/viewed/bookmarked
- **Search**: Full-text search across diagrams
- **Pagination**: For public feed and large diagram lists
- **Diagram versions**: Track changes over time
- **Comments**: Allow feedback on public diagrams
- **Collaborative editing**: Multiple owners per diagram
- **Export/Import**: Backup user's diagrams
- **API**: RESTful API for programmatic access
- **Tag suggestions**: AI-powered tag recommendations
- **Tag hierarchies**: Parent/child tag relationships
- **Smart filters**: Filters based on diagram attributes beyond tags

---

## Questions & Answers

**Q: Why join table instead of direct user_id?**
A: Enables many-to-many (user can own, fork, or bookmark diagrams). Cleaner than multiple FK columns.

**Q: Why remove concepts entirely?**
A: Tags with saved filters provide more flexibility. Users can view diagrams across multiple categories simultaneously. No rigid hierarchy.

**Q: Why tags instead of concepts?**
A: Tags allow:
- Multiple categorizations per diagram
- Flexible filtering (combine tags with AND/OR logic)
- No rigid hierarchy to maintain
- Users can create their own organization via saved filters

**Q: Why default visibility is :unlisted?**
A: Backward compatible with current behavior (accessible via link but not discoverable).

**Q: Can a diagram have multiple owners?**
A: Technically yes (multiple user_diagrams with is_owner: true), but current implementation assumes single owner (fork creates new diagram). Could support collaborative ownership in future.

**Q: What happens when diagram owner deletes account?**
A: Foreign key on user_diagrams is `on_delete: :delete_all`, so all relationships cascade. Diagrams themselves persist (orphaned). Could handle differently in production.

**Q: Performance of tag filtering?**
A: GIN index on tags array enables efficient queries. Should handle 100s of diagrams easily. Monitor with EXPLAIN ANALYZE if performance degrades.

**Q: Why separate "MY DIAGRAMS" and "FORKED DIAGRAMS"?**
A: Clear mental model for users. Owned diagrams (can edit) vs bookmarked (read-only).

**Q: Can users share saved filters?**
A: Not currently. Saved filters are user-specific. Could add sharing in future phase.

---

## Migration Execution Checklist

Before running migrations:
- [ ] Backup any existing data (if applicable)
- [ ] Review all migration changes
- [ ] Ensure foreign keys reference correct tables
- [ ] Verify indexes are on correct columns

Run migrations:
```bash
mix ecto.reset  # Drop, create, migrate, seed
```

After migrations:
- [ ] Verify schema with `psql` or similar
- [ ] Run test suite
- [ ] Manually test basic flows

---

## Implementation Timeline Estimate

Assuming 1 developer, working full-time:

- **Phase 1 (Data Model)**: 2-3 hours
- **Phase 2 (Core Functions)**: 4-6 hours
- **Phase 3 (Fork/Save)**: 2-3 hours
- **Phase 4 (Sidebar)**: 3-4 hours
- **Phase 5 (Actions)**: 4-5 hours
- **Phase 6 (Visibility)**: 2-3 hours
- **Phase 7 (Tests)**: 4-6 hours

**Total: ~21-30 hours** (3-4 days)

---

## Success Criteria

Implementation is complete when:
- ✅ All migrations run successfully
- ✅ All schemas compile without warnings
- ✅ All context functions have tests
- ✅ All LiveView features work as specified
- ✅ Authorization prevents unauthorized actions
- ✅ Visibility controls work for all diagram types
- ✅ Fork creates independent copy with tags
- ✅ Bookmark creates read-only reference
- ✅ Public diagrams toggle persists preference
- ✅ Tag filtering works correctly
- ✅ Saved filters can be created/edited/deleted
- ✅ Pin/unpin filters works
- ✅ Reorder filters works
- ✅ Tag management on diagrams works
- ✅ No concept references remain in code or UI
- ✅ Full test suite passes
- ✅ No Dialyzer warnings
- ✅ No Credo warnings

---

## Appendix: Example Seed Data

```elixir
# priv/repo/seeds.exs

alias DiagramForge.Repo
alias DiagramForge.Accounts.User
alias DiagramForge.Diagrams.{Concept, Diagram, UserDiagram, Document}

# Create users
{:ok, alice} = %User{}
  |> User.changeset(%{
    email: "alice@example.com",
    name: "Alice",
    provider: "github",
    provider_uid: "github_alice"
  })
  |> Repo.insert()

{:ok, bob} = %User{}
  |> User.changeset(%{
    email: "bob@example.com",
    name: "Bob",
    provider: "github",
    provider_uid: "github_bob"
  })
  |> Repo.insert()

# Create document
{:ok, doc} = %Document{}
  |> Document.changeset(%{
    title: "Sample Document",
    source_type: :pdf,
    path: "/tmp/sample.pdf",
    status: :ready
  })
  |> Repo.insert()

# Create concepts
{:ok, auth_concept} = %Concept{}
  |> Concept.changeset(%{
    name: "Authentication",
    category: "Security",
    document_id: doc.id,
    owner_id: alice.id
  })
  |> Repo.insert()

{:ok, db_concept} = %Concept{}
  |> Concept.changeset(%{
    name: "Database Design",
    category: "Architecture",
    document_id: doc.id,
    owner_id: alice.id
  })
  |> Repo.insert()

# Create diagram owned by Alice
{:ok, auth_diagram} = %Diagram{}
  |> Diagram.changeset(%{
    title: "OAuth Flow",
    slug: "oauth-flow-#{System.unique_integer()}",
    diagram_source: "graph TD\nA-->B",
    format: :mermaid,
    summary: "OAuth authentication flow",
    visibility: :public,
    concept_id: auth_concept.id
  })
  |> Repo.insert()

# Create ownership entry
%UserDiagram{}
|> UserDiagram.changeset(%{
  user_id: alice.id,
  diagram_id: auth_diagram.id,
  is_owner: true
})
|> Repo.insert!()

# Bob bookmarks Alice's diagram
%UserDiagram{}
|> UserDiagram.changeset(%{
  user_id: bob.id,
  diagram_id: auth_diagram.id,
  is_owner: false
})
|> Repo.insert!()

# Bob forks Alice's diagram
{:ok, forked_diagram} = %Diagram{}
  |> Diagram.changeset(%{
    title: "OAuth Flow (Bob's Fork)",
    slug: "oauth-flow-fork-#{System.unique_integer()}",
    diagram_source: "graph TD\nA-->B\nB-->C",
    format: :mermaid,
    summary: "Fork of OAuth flow with modifications",
    visibility: :unlisted,
    concept_id: auth_concept.id,
    forked_from_id: auth_diagram.id
  })
  |> Repo.insert()

# Create ownership for Bob's fork
%UserDiagram{}
|> UserDiagram.changeset(%{
  user_id: bob.id,
  diagram_id: forked_diagram.id,
  is_owner: true
})
|> Repo.insert!()

IO.puts("Seed data created!")
IO.puts("- 2 users: Alice, Bob")
IO.puts("- 2 concepts: Authentication, Database Design")
IO.puts("- 2 diagrams: Alice's public diagram, Bob's fork")
IO.puts("- Bob bookmarked Alice's diagram")
```

---

## End of Implementation Document

This document should be treated as a living document. Update it as implementation progresses, challenges are discovered, or requirements change.

**Next Steps:**
1. Review this document with team
2. Clarify any ambiguities
3. Begin Phase 1 implementation
4. Track progress through phases
5. Update document with learnings

Good luck with implementation!
