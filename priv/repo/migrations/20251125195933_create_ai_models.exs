defmodule DiagramForge.Repo.Migrations.CreateAiModels do
  use Ecto.Migration

  def change do
    create table(:ai_models, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :provider_id, references(:ai_providers, type: :binary_id, on_delete: :restrict),
        null: false

      add :name, :string, null: false
      add :api_name, :string, null: false
      add :is_active, :boolean, default: true, null: false
      add :is_default, :boolean, default: false, null: false
      add :capabilities, {:array, :string}, default: []

      timestamps()
    end

    create unique_index(:ai_models, [:provider_id, :api_name])
    create index(:ai_models, [:is_default], where: "is_default = true")
    create index(:ai_models, [:provider_id])
  end
end
