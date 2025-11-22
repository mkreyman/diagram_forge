defmodule DiagramForge.Diagrams.Diagram do
  @moduledoc """
  Schema for generated Mermaid diagrams.

  Diagrams are LLM-generated visual representations of technical concepts,
  stored in Mermaid format with supporting metadata.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "diagrams" do
    belongs_to :concept, DiagramForge.Diagrams.Concept
    belongs_to :document, DiagramForge.Diagrams.Document

    field :slug, :string
    field :title, :string

    field :domain, :string
    field :tags, {:array, :string}, default: []

    field :format, Ecto.Enum, values: [:mermaid, :plantuml], default: :mermaid
    field :diagram_source, :string
    field :summary, :string
    field :notes_md, :string

    timestamps()
  end

  def changeset(diagram, attrs) do
    diagram
    |> cast(attrs, [
      :concept_id,
      :document_id,
      :slug,
      :title,
      :domain,
      :tags,
      :format,
      :diagram_source,
      :summary,
      :notes_md
    ])
    |> validate_required([:title, :format, :diagram_source, :slug])
    |> unique_constraint(:slug)
  end
end
