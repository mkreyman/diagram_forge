defmodule DiagramForge.Diagrams.Diagram do
  @moduledoc """
  Schema for generated Mermaid diagrams.

  Diagrams are LLM-generated visual representations of technical concepts,
  stored in Mermaid format with supporting metadata.

  ## Organization

  Diagrams are organized using tags. Users can create saved filters to
  quickly view diagrams matching specific tag combinations.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "diagrams" do
    belongs_to :document, DiagramForge.Diagrams.Document
    belongs_to :user, DiagramForge.Accounts.User

    field :slug, :string
    field :title, :string

    field :tags, {:array, :string}, default: []

    field :format, Ecto.Enum, values: [:mermaid, :plantuml], default: :mermaid
    field :diagram_source, :string
    field :summary, :string
    field :notes_md, :string
    field :created_by_superadmin, :boolean, default: false

    timestamps()
  end

  def changeset(diagram, attrs) do
    diagram
    |> cast(attrs, [
      :document_id,
      :user_id,
      :slug,
      :title,
      :tags,
      :format,
      :diagram_source,
      :summary,
      :notes_md,
      :created_by_superadmin
    ])
    |> validate_required([:title, :format, :diagram_source, :slug])
    |> unique_constraint(:slug)
  end
end
