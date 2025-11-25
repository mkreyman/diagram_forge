defmodule DiagramForge.Repo.Migrations.CreateTokenUsage do
  use Ecto.Migration

  def change do
    create table(:token_usage, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :model_id, references(:ai_models, type: :binary_id, on_delete: :restrict), null: false
      add :operation, :string, null: false
      add :input_tokens, :integer, null: false
      add :output_tokens, :integer, null: false
      add :total_tokens, :integer, null: false
      add :cost_cents, :integer
      add :metadata, :map, default: %{}

      timestamps(updated_at: false)
    end

    create index(:token_usage, [:user_id, :inserted_at])
    create index(:token_usage, [:inserted_at])
    create index(:token_usage, [:model_id])
  end
end
