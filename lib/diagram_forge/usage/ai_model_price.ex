defmodule DiagramForge.Usage.AIModelPrice do
  @moduledoc """
  Schema for AI model pricing with effective date ranges.
  Supports tracking price history as providers change pricing.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "ai_model_prices" do
    field :input_price_per_million, :decimal
    field :output_price_per_million, :decimal
    field :effective_from, :utc_datetime
    field :effective_until, :utc_datetime

    belongs_to :model, DiagramForge.Usage.AIModel

    timestamps()
  end

  def changeset(price, attrs) do
    price
    |> cast(attrs, [
      :input_price_per_million,
      :output_price_per_million,
      :effective_from,
      :effective_until,
      :model_id
    ])
    |> validate_required([
      :input_price_per_million,
      :output_price_per_million,
      :effective_from,
      :model_id
    ])
    |> validate_number(:input_price_per_million, greater_than_or_equal_to: 0)
    |> validate_number(:output_price_per_million, greater_than_or_equal_to: 0)
    |> validate_effective_dates()
    |> foreign_key_constraint(:model_id)
  end

  defp validate_effective_dates(changeset) do
    effective_from = get_field(changeset, :effective_from)
    effective_until = get_field(changeset, :effective_until)

    if effective_from && effective_until &&
         DateTime.compare(effective_until, effective_from) != :gt do
      add_error(changeset, :effective_until, "must be after effective_from")
    else
      changeset
    end
  end
end
