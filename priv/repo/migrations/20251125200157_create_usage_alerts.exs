defmodule DiagramForge.Repo.Migrations.CreateUsageAlerts do
  use Ecto.Migration

  def change do
    create table(:usage_alerts, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :threshold_id,
          references(:usage_alert_thresholds, type: :binary_id, on_delete: :delete_all),
          null: false

      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all)
      add :period_start, :date, null: false
      add :period_end, :date, null: false
      add :amount_cents, :integer, null: false
      add :email_sent_at, :utc_datetime
      add :acknowledged_at, :utc_datetime
      add :acknowledged_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)

      timestamps(updated_at: false)
    end

    create index(:usage_alerts, [:threshold_id, :period_start])
    create index(:usage_alerts, [:user_id, :period_start])
    create index(:usage_alerts, [:acknowledged_at], where: "acknowledged_at IS NULL")
  end
end
