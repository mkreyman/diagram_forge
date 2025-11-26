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
      :title,
      :tags,
      :format,
      :visibility,
      :diagram_source,
      :summary,
      :notes_md
    ])
    |> validate_required([:title, :format, :diagram_source])
    |> validate_inclusion(:visibility, [:private, :unlisted, :public])
    |> foreign_key_constraint(:document_id)
    |> foreign_key_constraint(:forked_from_id)
  end
end
