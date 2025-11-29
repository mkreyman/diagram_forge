# Admin Bulk Visibility Actions

## Overview

Add bulk visibility actions to the admin Diagrams panel, allowing administrators to change the visibility of multiple diagrams at once.

## User Story

As an admin, I want to select multiple diagrams and change their visibility in bulk, so I can efficiently manage diagram access levels without editing each one individually.

## Current State

- Admin panel uses Backpex at `/admin/diagrams`
- `DiagramResource` displays diagrams with individual visibility field (Private/Unlisted/Public)
- No bulk actions currently exist
- `update_diagram/3` in Diagrams context requires user authorization

## Proposed Solution

### Approach: Backpex Item Actions

Backpex supports "item actions" - operations that can be performed on one or more selected items. We'll create three item actions:

1. **Make Public** - Sets visibility to `:public`
2. **Make Unlisted** - Sets visibility to `:unlisted`
3. **Make Private** - Sets visibility to `:private`

### Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Admin Diagrams List                       │
│  ┌──┬────────────────────────────────────────────────────┐  │
│  │☑ │ ID      │ Title           │ Visibility │ Format   │  │
│  ├──┼─────────┼─────────────────┼────────────┼──────────┤  │
│  │☑ │ abc123  │ User Flow       │ Private    │ Mermaid  │  │
│  │☑ │ def456  │ System Arch     │ Private    │ PlantUML │  │
│  │☐ │ ghi789  │ Data Model      │ Public     │ Mermaid  │  │
│  └──┴─────────┴─────────────────┴────────────┴──────────┘  │
│                                                              │
│  [▼ Bulk Actions]  ← Dropdown with visibility options        │
│    ├─ Make Public                                            │
│    ├─ Make Unlisted                                          │
│    └─ Make Private                                           │
└─────────────────────────────────────────────────────────────┘
```

## Implementation Details

### Files to Create

#### 1. `lib/diagram_forge_web/admin/item_actions/make_public.ex`

```elixir
defmodule DiagramForgeWeb.Admin.ItemAction.MakePublic do
  @moduledoc """
  Backpex item action to bulk-set diagram visibility to public.
  """

  use BackpexWeb, :item_action

  alias DiagramForge.Diagrams

  @impl Backpex.ItemAction
  def icon(assigns, _item) do
    ~H"""
    <Backpex.HTML.CoreComponents.icon
      name="hero-globe-alt"
      class="h-5 w-5 cursor-pointer transition duration-75 hover:scale-110 hover:text-green-600"
    />
    """
  end

  @impl Backpex.ItemAction
  def label(_assigns, _item), do: "Make Public"

  @impl Backpex.ItemAction
  def confirm(assigns) do
    count = Enum.count(assigns.selected_items)

    if count > 1 do
      "Make #{count} diagrams public? They will be visible to everyone."
    else
      "Make this diagram public? It will be visible to everyone."
    end
  end

  @impl Backpex.ItemAction
  def handle(socket, items, _data) do
    case Diagrams.admin_bulk_update_visibility(items, :public) do
      {:ok, count} ->
        socket
        |> clear_flash()
        |> put_flash(:info, "#{count} diagram(s) set to public")
        |> ok()

      {:error, reason} ->
        socket
        |> clear_flash()
        |> put_flash(:error, "Failed to update: #{inspect(reason)}")
        |> ok()
    end
  end
end
```

#### 2. `lib/diagram_forge_web/admin/item_actions/make_unlisted.ex`

```elixir
defmodule DiagramForgeWeb.Admin.ItemAction.MakeUnlisted do
  @moduledoc """
  Backpex item action to bulk-set diagram visibility to unlisted.
  """

  use BackpexWeb, :item_action

  alias DiagramForge.Diagrams

  @impl Backpex.ItemAction
  def icon(assigns, _item) do
    ~H"""
    <Backpex.HTML.CoreComponents.icon
      name="hero-link"
      class="h-5 w-5 cursor-pointer transition duration-75 hover:scale-110 hover:text-yellow-600"
    />
    """
  end

  @impl Backpex.ItemAction
  def label(_assigns, _item), do: "Make Unlisted"

  @impl Backpex.ItemAction
  def confirm(assigns) do
    count = Enum.count(assigns.selected_items)

    if count > 1 do
      "Make #{count} diagrams unlisted? They will be accessible via direct link only."
    else
      "Make this diagram unlisted? It will be accessible via direct link only."
    end
  end

  @impl Backpex.ItemAction
  def handle(socket, items, _data) do
    case Diagrams.admin_bulk_update_visibility(items, :unlisted) do
      {:ok, count} ->
        socket
        |> clear_flash()
        |> put_flash(:info, "#{count} diagram(s) set to unlisted")
        |> ok()

      {:error, reason} ->
        socket
        |> clear_flash()
        |> put_flash(:error, "Failed to update: #{inspect(reason)}")
        |> ok()
    end
  end
end
```

#### 3. `lib/diagram_forge_web/admin/item_actions/make_private.ex`

```elixir
defmodule DiagramForgeWeb.Admin.ItemAction.MakePrivate do
  @moduledoc """
  Backpex item action to bulk-set diagram visibility to private.
  """

  use BackpexWeb, :item_action

  alias DiagramForge.Diagrams

  @impl Backpex.ItemAction
  def icon(assigns, _item) do
    ~H"""
    <Backpex.HTML.CoreComponents.icon
      name="hero-lock-closed"
      class="h-5 w-5 cursor-pointer transition duration-75 hover:scale-110 hover:text-red-600"
    />
    """
  end

  @impl Backpex.ItemAction
  def label(_assigns, _item), do: "Make Private"

  @impl Backpex.ItemAction
  def confirm(assigns) do
    count = Enum.count(assigns.selected_items)

    if count > 1 do
      "Make #{count} diagrams private? Only owners will be able to access them."
    else
      "Make this diagram private? Only the owner will be able to access it."
    end
  end

  @impl Backpex.ItemAction
  def handle(socket, items, _data) do
    case Diagrams.admin_bulk_update_visibility(items, :private) do
      {:ok, count} ->
        socket
        |> clear_flash()
        |> put_flash(:info, "#{count} diagram(s) set to private")
        |> ok()

      {:error, reason} ->
        socket
        |> clear_flash()
        |> put_flash(:error, "Failed to update: #{inspect(reason)}")
        |> ok()
    end
  end
end
```

### Files to Modify

#### 1. Context: `lib/diagram_forge/diagrams.ex`

Add admin bulk update function:

```elixir
@doc """
Admin-only function to bulk update diagram visibility.
Bypasses user authorization checks.

## Examples

    iex> admin_bulk_update_visibility(diagrams, :public)
    {:ok, 5}

    iex> admin_bulk_update_visibility([], :public)
    {:ok, 0}
"""
def admin_bulk_update_visibility([], _visibility), do: {:ok, 0}

def admin_bulk_update_visibility(diagrams, visibility)
    when visibility in [:public, :unlisted, :private] do
  ids = Enum.map(diagrams, & &1.id)

  {count, _} =
    from(d in Diagram, where: d.id in ^ids)
    |> Repo.update_all(set: [
      visibility: visibility,
      updated_at: DateTime.utc_now() |> DateTime.truncate(:second)
    ])

  {:ok, count}
end
```

#### 2. Resource: `lib/diagram_forge_web/admin/resources/diagram_resource.ex`

Add item_actions callback:

```elixir
@impl Backpex.LiveResource
def item_actions(default_actions) do
  # Keep default show/edit/delete, add visibility actions
  Keyword.merge(default_actions, [
    make_public: %{module: DiagramForgeWeb.Admin.ItemAction.MakePublic, only: [:index]},
    make_unlisted: %{module: DiagramForgeWeb.Admin.ItemAction.MakeUnlisted, only: [:index]},
    make_private: %{module: DiagramForgeWeb.Admin.ItemAction.MakePrivate, only: [:index]}
  ])
end
```

## Testing

### Test File: `test/diagram_forge/diagrams_admin_test.exs`

```elixir
defmodule DiagramForge.DiagramsAdminTest do
  use DiagramForge.DataCase, async: true

  alias DiagramForge.Diagrams
  alias DiagramForge.Diagrams.Diagram

  import DiagramForge.Fixtures

  describe "admin_bulk_update_visibility/2" do
    setup do
      diagrams = [
        fixture(:diagram, visibility: :private),
        fixture(:diagram, visibility: :private),
        fixture(:diagram, visibility: :unlisted)
      ]

      %{diagrams: diagrams}
    end

    test "updates multiple diagrams to public", %{diagrams: diagrams} do
      assert {:ok, 3} = Diagrams.admin_bulk_update_visibility(diagrams, :public)

      for diagram <- diagrams do
        updated = Repo.get!(Diagram, diagram.id)
        assert updated.visibility == :public
      end
    end

    test "updates multiple diagrams to unlisted", %{diagrams: diagrams} do
      assert {:ok, 3} = Diagrams.admin_bulk_update_visibility(diagrams, :unlisted)

      for diagram <- diagrams do
        updated = Repo.get!(Diagram, diagram.id)
        assert updated.visibility == :unlisted
      end
    end

    test "updates multiple diagrams to private", %{diagrams: diagrams} do
      assert {:ok, 3} = Diagrams.admin_bulk_update_visibility(diagrams, :private)

      for diagram <- diagrams do
        updated = Repo.get!(Diagram, diagram.id)
        assert updated.visibility == :private
      end
    end

    test "returns 0 count for empty list" do
      assert {:ok, 0} = Diagrams.admin_bulk_update_visibility([], :public)
    end

    test "updates timestamp on visibility change", %{diagrams: [diagram | _]} do
      original_updated_at = diagram.updated_at

      # Small delay to ensure time difference
      Process.sleep(10)

      {:ok, 1} = Diagrams.admin_bulk_update_visibility([diagram], :public)

      updated = Repo.get!(Diagram, diagram.id)
      assert DateTime.compare(updated.updated_at, original_updated_at) == :gt
    end

    test "raises on invalid visibility" do
      diagram = fixture(:diagram)

      assert_raise FunctionClauseError, fn ->
        Diagrams.admin_bulk_update_visibility([diagram], :invalid)
      end
    end
  end
end
```

## Technical Notes

### Backpex ItemAction Pattern

The `use BackpexWeb, :item_action` macro provides:
- `use Phoenix.Component`
- `use Backpex.ItemAction` (behavior)
- `import Phoenix.LiveView` (provides `clear_flash/1`, `put_flash/3`)
- `ok/1` helper function (wraps socket in `{:ok, socket}`)

### Return Value Pattern

Item actions must return `{:ok, socket}` or `{:error, changeset}`. Flash messages are set on the socket itself:

```elixir
# Correct pattern
socket
|> clear_flash()
|> put_flash(:info, "Success message")
|> ok()

# NOT this (wrong)
{:ok, socket, "message"}
```

### DateTime Handling

Use `DateTime.truncate(:second)` to match Ecto's timestamp precision:

```elixir
updated_at: DateTime.utc_now() |> DateTime.truncate(:second)
```

## UX Flow

1. Admin navigates to `/admin/diagrams`
2. Checkboxes appear next to each diagram row
3. Admin selects one or more diagrams
4. A "Bulk Actions" dropdown appears (or is always visible)
5. Admin selects "Make Public", "Make Unlisted", or "Make Private"
6. Confirmation dialog appears with dynamic count: "Make 3 diagrams public?"
7. Admin confirms
8. Success toast: "3 diagram(s) set to public"
9. Table refreshes showing updated visibility

## Security Considerations

- All actions require superadmin access (enforced by `can?/3` callbacks on DiagramResource)
- Bulk update function is in context, not exposed via public API
- Confirmation dialogs prevent accidental bulk changes
- Authorization is inherited from resource level (no additional checks needed in item actions)

## Future Enhancements

- Filter by user before bulk action (e.g., "Make all of User X's diagrams public")
- Batch moderation approval alongside visibility changes
- Undo functionality (time-limited)
- Activity log for admin actions
