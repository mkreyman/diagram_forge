defmodule DiagramForgeWeb.Admin.DiagramResource do
  @moduledoc """
  Backpex resource for managing Diagrams in the admin panel.
  """

  alias DiagramForge.Diagrams.Diagram

  use Backpex.LiveResource,
    adapter_config: [
      schema: Diagram,
      repo: DiagramForge.Repo,
      update_changeset: &__MODULE__.changeset/3,
      create_changeset: &__MODULE__.changeset/3
    ],
    layout: {DiagramForgeWeb.Admin.Layouts, :admin}

  @doc false
  def changeset(item, attrs, _metadata) do
    Diagram.changeset(item, attrs)
  end

  @impl Backpex.LiveResource
  def singular_name, do: "Diagram"

  @impl Backpex.LiveResource
  def plural_name, do: "Diagrams"

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
      visibility: %{
        module: Backpex.Fields.Select,
        label: "Visibility",
        options: [
          {"Private", :private},
          {"Unlisted", :unlisted},
          {"Public", :public}
        ]
      },
      format: %{
        module: Backpex.Fields.Select,
        label: "Format",
        options: [
          {"Mermaid", :mermaid},
          {"PlantUML", :plantuml}
        ]
      },
      tags: %{
        module: Backpex.Fields.Text,
        label: "Tags",
        render: fn assigns ->
          tags_str =
            case assigns.value do
              nil -> "-"
              [] -> "-"
              tags -> Enum.join(tags, ", ")
            end

          assigns = assign(assigns, :tags_str, tags_str)

          ~H"""
          <span class="text-sm">{@tags_str}</span>
          """
        end
      },
      document: %{
        module: Backpex.Fields.BelongsTo,
        label: "Document",
        display_field: :title,
        options_query: fn query, _assigns ->
          import Ecto.Query
          from(d in query, order_by: [desc: d.inserted_at], limit: 100)
        end
      },
      forked_from: %{
        module: Backpex.Fields.BelongsTo,
        label: "Forked From",
        display_field: :title,
        only: [:show],
        options_query: fn query, _assigns ->
          import Ecto.Query
          from(d in query, order_by: [desc: d.inserted_at], limit: 100)
        end
      },
      summary: %{
        module: Backpex.Fields.Textarea,
        label: "Summary",
        searchable: true,
        only: [:show, :edit, :new]
      },
      diagram_source: %{
        module: Backpex.Fields.Textarea,
        label: "Diagram Source",
        only: [:show, :edit, :new]
      },
      notes_md: %{
        module: Backpex.Fields.Textarea,
        label: "Notes (Markdown)",
        searchable: true,
        only: [:show, :edit, :new]
      },
      moderation_status: %{
        module: Backpex.Fields.Select,
        label: "Moderation",
        options: [
          {"Pending", :pending},
          {"Approved", :approved},
          {"Rejected", :rejected},
          {"Manual Review", :manual_review}
        ],
        render: fn assigns ->
          {color, text} =
            case assigns.value do
              :pending -> {"bg-yellow-100 text-yellow-800", "Pending"}
              :approved -> {"bg-green-100 text-green-800", "Approved"}
              :rejected -> {"bg-red-100 text-red-800", "Rejected"}
              :manual_review -> {"bg-orange-100 text-orange-800", "Review"}
              _ -> {"bg-gray-100 text-gray-800", "Unknown"}
            end

          assigns = assign(assigns, color: color, text: text)

          ~H"""
          <span class={"inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium #{@color}"}>
            {@text}
          </span>
          """
        end
      },
      moderation_reason: %{
        module: Backpex.Fields.Textarea,
        label: "Moderation Reason",
        only: [:show]
      },
      moderated_at: %{
        module: Backpex.Fields.DateTime,
        label: "Moderated At",
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
