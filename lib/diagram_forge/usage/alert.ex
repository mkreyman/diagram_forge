defmodule DiagramForge.Usage.Alert do
  @moduledoc """
  Schema for usage alert history.
  Records when thresholds are exceeded and tracks acknowledgement.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "usage_alerts" do
    field :period_start, :date
    field :period_end, :date
    field :amount_cents, :integer
    field :email_sent_at, :utc_datetime
    field :acknowledged_at, :utc_datetime

    belongs_to :threshold, DiagramForge.Usage.AlertThreshold
    belongs_to :user, DiagramForge.Accounts.User
    belongs_to :acknowledged_by, DiagramForge.Accounts.User

    timestamps(updated_at: false)
  end

  def changeset(alert, attrs) do
    alert
    |> cast(attrs, [
      :period_start,
      :period_end,
      :amount_cents,
      :email_sent_at,
      :acknowledged_at,
      :threshold_id,
      :user_id,
      :acknowledged_by_id
    ])
    |> validate_required([:period_start, :period_end, :amount_cents, :threshold_id])
    |> validate_number(:amount_cents, greater_than: 0)
    |> validate_period_dates()
    |> foreign_key_constraint(:threshold_id)
    |> foreign_key_constraint(:user_id)
    |> foreign_key_constraint(:acknowledged_by_id)
  end

  def acknowledge_changeset(alert, admin_user_id) do
    alert
    |> cast(%{}, [])
    |> put_change(:acknowledged_at, DateTime.utc_now() |> DateTime.truncate(:second))
    |> put_change(:acknowledged_by_id, admin_user_id)
  end

  defp validate_period_dates(changeset) do
    period_start = get_field(changeset, :period_start)
    period_end = get_field(changeset, :period_end)

    if period_start && period_end && Date.compare(period_end, period_start) == :lt do
      add_error(changeset, :period_end, "must be on or after period_start")
    else
      changeset
    end
  end
end
