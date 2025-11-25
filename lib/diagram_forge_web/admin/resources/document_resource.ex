defmodule DiagramForgeWeb.Admin.DocumentResource do
  @moduledoc """
  Backpex resource for managing Documents in the admin panel.
  """

  alias DiagramForge.Diagrams.Document

  use Backpex.LiveResource,
    adapter_config: [
      schema: Document,
      repo: DiagramForge.Repo,
      update_changeset: &__MODULE__.changeset/3,
      create_changeset: &__MODULE__.changeset/3
    ],
    layout: {DiagramForgeWeb.Admin.Layouts, :admin}

  @doc false
  def changeset(item, attrs, _metadata) do
    Document.changeset(item, attrs)
  end

  @impl Backpex.LiveResource
  def singular_name, do: "Document"

  @impl Backpex.LiveResource
  def plural_name, do: "Documents"

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
      title: %{
        module: Backpex.Fields.Text,
        label: "Title",
        searchable: true
      },
      user: %{
        module: Backpex.Fields.BelongsTo,
        label: "User",
        display_field: :email,
        options_query: fn query, _assigns ->
          import Ecto.Query
          from(u in query, order_by: [asc: u.email])
        end
      },
      source_type: %{
        module: Backpex.Fields.Select,
        label: "Source Type",
        options: [
          {"PDF", :pdf},
          {"Markdown", :markdown}
        ]
      },
      status: %{
        module: Backpex.Fields.Select,
        label: "Status",
        options: [
          {"Uploaded", :uploaded},
          {"Processing", :processing},
          {"Ready", :ready},
          {"Error", :error}
        ]
      },
      path: %{
        module: Backpex.Fields.Text,
        label: "File Path",
        only: [:show]
      },
      error_message: %{
        module: Backpex.Fields.Textarea,
        label: "Error Message",
        only: [:show]
      },
      raw_text: %{
        module: Backpex.Fields.Textarea,
        label: "Raw Text",
        searchable: true,
        only: [:show]
      },
      completed_at: %{
        module: Backpex.Fields.DateTime,
        label: "Completed At",
        only: [:show]
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
