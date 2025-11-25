defmodule DiagramForge.Usage.DailyAggregate do
  @moduledoc """
  Schema for daily token usage aggregates per user.
  Used for efficient dashboard queries and cost reporting.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "usage_daily_aggregates" do
    field :date, :date
    field :request_count, :integer, default: 0
    field :input_tokens, :integer, default: 0
    field :output_tokens, :integer, default: 0
    field :total_tokens, :integer, default: 0
    field :cost_cents, :integer, default: 0

    belongs_to :user, DiagramForge.Accounts.User
    belongs_to :model, DiagramForge.Usage.AIModel

    timestamps()
  end

  def changeset(aggregate, attrs) do
    aggregate
    |> cast(attrs, [
      :date,
      :request_count,
      :input_tokens,
      :output_tokens,
      :total_tokens,
      :cost_cents,
      :user_id,
      :model_id
    ])
    |> validate_required([:date, :model_id])
    |> validate_number(:request_count, greater_than_or_equal_to: 0)
    |> validate_number(:input_tokens, greater_than_or_equal_to: 0)
    |> validate_number(:output_tokens, greater_than_or_equal_to: 0)
    |> validate_number(:total_tokens, greater_than_or_equal_to: 0)
    |> validate_number(:cost_cents, greater_than_or_equal_to: 0)
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:model_id)
    |> unique_constraint([:user_id, :date, :model_id])
  end
end
