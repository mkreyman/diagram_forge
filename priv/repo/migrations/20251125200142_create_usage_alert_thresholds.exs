defmodule DiagramForge.Repo.Migrations.CreateUsageAlertThresholds do
  use Ecto.Migration

  def change do
    create table(:usage_alert_thresholds, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :threshold_cents, :integer, null: false
      add :period, :string, null: false
      add :scope, :string, null: false
      add :is_active, :boolean, default: true, null: false
      add :notify_email, :boolean, default: true, null: false
      add :notify_dashboard, :boolean, default: true, null: false

      timestamps()
    end

    create unique_index(:usage_alert_thresholds, [:name])
  end
end
