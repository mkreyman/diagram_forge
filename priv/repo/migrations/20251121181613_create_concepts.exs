defmodule DiagramForge.Repo.Migrations.CreateConcepts do
  use Ecto.Migration

  def change do
    create table(:concepts, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :document_id, references(:documents, type: :binary_id, on_delete: :delete_all),
        null: false

      add :name, :string, null: false
      add :short_description, :text
      add :category, :string, null: false

      timestamps()
    end

    create index(:concepts, [:document_id, :name])
    create index(:concepts, [:document_id])
  end
end
