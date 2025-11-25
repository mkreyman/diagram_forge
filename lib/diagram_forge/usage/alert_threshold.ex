defmodule DiagramForge.Usage.AlertThreshold do
  @moduledoc """
  Schema for usage alert threshold configuration.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @periods ~w(daily monthly)
  @scopes ~w(per_user total)

  schema "usage_alert_thresholds" do
    field :name, :string
    field :threshold_cents, :integer
    field :period, :string
    field :scope, :string
    field :is_active, :boolean, default: true
    field :notify_email, :boolean, default: true
    field :notify_dashboard, :boolean, default: true

    has_many :alerts, DiagramForge.Usage.Alert, foreign_key: :threshold_id

    timestamps()
  end

  def changeset(threshold, attrs) do
    threshold
    |> cast(attrs, [
      :name,
      :threshold_cents,
      :period,
      :scope,
      :is_active,
      :notify_email,
      :notify_dashboard
    ])
    |> validate_required([:name, :threshold_cents, :period, :scope])
    |> validate_number(:threshold_cents, greater_than: 0)
    |> validate_inclusion(:period, @periods)
    |> validate_inclusion(:scope, @scopes)
    |> unique_constraint(:name)
  end

  def periods, do: @periods
  def scopes, do: @scopes
end
