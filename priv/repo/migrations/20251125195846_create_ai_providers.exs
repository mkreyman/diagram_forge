defmodule DiagramForge.Repo.Migrations.CreateAiProviders do
  use Ecto.Migration

  def change do
    create table(:ai_providers, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :slug, :string, null: false
      add :api_base_url, :string
      add :is_active, :boolean, default: true, null: false

      timestamps()
    end

    create unique_index(:ai_providers, [:slug])
  end
end
