defmodule DiagramForge.Usage.TokenUsage do
  @moduledoc """
  Schema for per-request token usage logging.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "token_usage" do
    field :operation, :string
    field :input_tokens, :integer
    field :output_tokens, :integer
    field :total_tokens, :integer
    field :cost_cents, :integer
    field :metadata, :map, default: %{}

    belongs_to :user, DiagramForge.Accounts.User
    belongs_to :model, DiagramForge.Usage.AIModel

    timestamps(updated_at: false)
  end

  def changeset(usage, attrs) do
    usage
    |> cast(attrs, [
      :operation,
      :input_tokens,
      :output_tokens,
      :total_tokens,
      :cost_cents,
      :metadata,
      :user_id,
      :model_id
    ])
    |> validate_required([:operation, :input_tokens, :output_tokens, :total_tokens, :model_id])
    |> validate_number(:input_tokens, greater_than_or_equal_to: 0)
    |> validate_number(:output_tokens, greater_than_or_equal_to: 0)
    |> validate_number(:total_tokens, greater_than_or_equal_to: 0)
    |> validate_inclusion(:operation, ["diagram_generation", "syntax_fix"])
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:model_id)
  end
end
