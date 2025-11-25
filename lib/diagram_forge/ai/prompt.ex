defmodule DiagramForge.AI.Prompt do
  @moduledoc """
  Schema for customizable AI prompts.

  This schema stores admin-customized versions of AI prompts. When a prompt
  is not found in the database, the hardcoded default from `DiagramForge.AI.Prompts`
  is used instead.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "prompts" do
    field :key, :string
    field :content, :string
    field :description, :string

    timestamps()
  end

  @required_fields ~w(key content)a
  @optional_fields ~w(description)a

  def changeset(prompt, attrs) do
    prompt
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> unique_constraint(:key)
  end
end
