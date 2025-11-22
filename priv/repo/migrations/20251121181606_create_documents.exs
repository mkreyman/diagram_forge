defmodule DiagramForge.Repo.Migrations.CreateDocuments do
  use Ecto.Migration

  def change do
    create table(:documents, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :title, :string, null: false
      add :source_type, :string, null: false
      add :path, :string, null: false
      add :raw_text, :text
      add :status, :string, null: false, default: "uploaded"
      add :error_message, :text
      add :completed_at, :utc_datetime

      timestamps()
    end

    create index(:documents, [:status])
  end
end
