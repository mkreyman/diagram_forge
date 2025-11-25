defmodule DiagramForge.Usage.AIModel do
  @moduledoc """
  Schema for AI models (gpt-4o-mini, gpt-4o, claude-3-sonnet, etc.).
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "ai_models" do
    field :name, :string
    field :api_name, :string
    field :is_active, :boolean, default: true
    field :is_default, :boolean, default: false
    field :capabilities, {:array, :string}, default: []

    belongs_to :provider, DiagramForge.Usage.AIProvider
    has_many :prices, DiagramForge.Usage.AIModelPrice, foreign_key: :model_id
    has_many :token_usages, DiagramForge.Usage.TokenUsage, foreign_key: :model_id

    timestamps()
  end

  def changeset(model, attrs) do
    model
    |> cast(attrs, [:name, :api_name, :is_active, :is_default, :capabilities, :provider_id])
    |> validate_required([:name, :api_name, :provider_id])
    |> validate_format(:api_name, ~r/^[a-z0-9._-]+$/,
      message: "must be lowercase alphanumeric with dots, dashes, or underscores"
    )
    |> foreign_key_constraint(:provider_id)
    |> unique_constraint([:provider_id, :api_name])
  end
end
