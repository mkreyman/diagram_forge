defmodule DiagramForge.Repo.Migrations.CreateAiModelPrices do
  use Ecto.Migration

  def change do
    create table(:ai_model_prices, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :model_id, references(:ai_models, type: :binary_id, on_delete: :delete_all), null: false
      add :input_price_per_million, :decimal, precision: 12, scale: 6, null: false
      add :output_price_per_million, :decimal, precision: 12, scale: 6, null: false
      add :effective_from, :utc_datetime, null: false
      add :effective_until, :utc_datetime

      timestamps()
    end

    create index(:ai_model_prices, [:model_id, :effective_from])
    create index(:ai_model_prices, [:model_id])
  end
end
