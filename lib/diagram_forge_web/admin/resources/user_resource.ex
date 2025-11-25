defmodule DiagramForgeWeb.Admin.UserResource do
  @moduledoc """
  Backpex resource for managing Users in the admin panel.
  """

  alias DiagramForge.Accounts.User

  use Backpex.LiveResource,
    adapter_config: [
      schema: User,
      repo: DiagramForge.Repo,
      update_changeset: &__MODULE__.changeset/3,
      create_changeset: &__MODULE__.changeset/3
    ],
    layout: {DiagramForgeWeb.Admin.Layouts, :admin}

  @doc false
  def changeset(item, attrs, _metadata) do
    User.changeset(item, attrs)
  end

  @impl Backpex.LiveResource
  def singular_name, do: "User"

  @impl Backpex.LiveResource
  def plural_name, do: "Users"

  @impl Backpex.LiveResource
  def fields do
    [
      id: %{
        module: Backpex.Fields.Text,
        label: "ID",
        searchable: true,
        render: fn assigns ->
          short_id =
            assigns.value
            |> to_string()
            |> String.slice(0..7)

          assigns = assign(assigns, :short_id, short_id)

          ~H"""
          <span title={@value} class="font-mono text-xs">{@short_id}...</span>
          """
        end
      },
      email: %{
        module: Backpex.Fields.Text,
        label: "Email",
        searchable: true
      },
      name: %{
        module: Backpex.Fields.Text,
        label: "Name",
        searchable: true
      },
      provider: %{
        module: Backpex.Fields.Text,
        label: "Provider"
      },
      provider_uid: %{
        module: Backpex.Fields.Text,
        label: "Provider UID",
        searchable: true,
        only: [:show]
      },
      avatar_url: %{
        module: Backpex.Fields.Text,
        label: "Avatar URL",
        only: [:show]
      },
      show_public_diagrams: %{
        module: Backpex.Fields.Boolean,
        label: "Show Public Diagrams"
      },
      last_sign_in_at: %{
        module: Backpex.Fields.DateTime,
        label: "Last Sign In"
      },
      inserted_at: %{
        module: Backpex.Fields.DateTime,
        label: "Created",
        only: [:index, :show]
      },
      updated_at: %{
        module: Backpex.Fields.DateTime,
        label: "Updated",
        only: [:show]
      }
    ]
  end

  @impl Backpex.LiveResource
  def can?(assigns, :index, _item), do: superadmin?(assigns)
  def can?(assigns, :new, _item), do: superadmin?(assigns)
  def can?(assigns, :show, _item), do: superadmin?(assigns)
  def can?(assigns, :edit, _item), do: superadmin?(assigns)
  def can?(assigns, :delete, _item), do: superadmin?(assigns)
  def can?(_assigns, _action, _item), do: false

  defp superadmin?(assigns) do
    Map.get(assigns, :is_superadmin, false)
  end
end
