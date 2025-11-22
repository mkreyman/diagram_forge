defmodule DiagramForge.Diagrams.Concept do
  @moduledoc """
  Schema for technical concepts extracted from documents.

  Concepts represent key technical ideas identified by LLM analysis
  that are suitable for visualization in diagrams.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "concepts" do
    belongs_to :document, DiagramForge.Diagrams.Document

    field :name, :string
    field :short_description, :string
    field :category, :string

    has_many :diagrams, DiagramForge.Diagrams.Diagram

    timestamps()
  end

  def changeset(concept, attrs) do
    concept
    |> cast(attrs, [:document_id, :name, :short_description, :category])
    |> validate_required([:name, :category])
    |> unique_constraint(:name,
      name: :concepts_name_index,
      message: "already exists"
    )
  end
end
