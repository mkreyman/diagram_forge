defmodule DiagramForge.Repo.Migrations.CreateUsageDailyAggregates do
  use Ecto.Migration

  def change do
    create table(:usage_daily_aggregates, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all)
      add :model_id, references(:ai_models, type: :binary_id, on_delete: :restrict), null: false
      add :date, :date, null: false
      add :request_count, :integer, default: 0, null: false
      add :input_tokens, :integer, default: 0, null: false
      add :output_tokens, :integer, default: 0, null: false
      add :total_tokens, :integer, default: 0, null: false
      add :cost_cents, :integer, default: 0, null: false

      timestamps()
    end

    create unique_index(:usage_daily_aggregates, [:user_id, :date, :model_id])
    create index(:usage_daily_aggregates, [:date])
    create index(:usage_daily_aggregates, [:user_id, :date])
  end
end
