defmodule DiagramForge.Usage.AIProvider do
  @moduledoc """
  Schema for AI providers (OpenAI, Anthropic, etc.).
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "ai_providers" do
    field :name, :string
    field :slug, :string
    field :api_base_url, :string
    field :is_active, :boolean, default: true

    has_many :models, DiagramForge.Usage.AIModel, foreign_key: :provider_id

    timestamps()
  end

  def changeset(provider, attrs) do
    provider
    |> cast(attrs, [:name, :slug, :api_base_url, :is_active])
    |> validate_required([:name, :slug])
    |> validate_format(:slug, ~r/^[a-z0-9_-]+$/,
      message: "must be lowercase alphanumeric with dashes or underscores"
    )
    |> unique_constraint(:slug)
  end
end
