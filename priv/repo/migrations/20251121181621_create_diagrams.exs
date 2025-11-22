defmodule DiagramForge.Repo.Migrations.CreateDiagrams do
  use Ecto.Migration

  def change do
    create table(:diagrams, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :concept_id, references(:concepts, type: :binary_id, on_delete: :nilify_all)
      add :document_id, references(:documents, type: :binary_id, on_delete: :nilify_all)
      add :slug, :string, null: false
      add :title, :string, null: false
      add :domain, :string
      add :tags, {:array, :string}, default: []
      add :format, :string, null: false, default: "mermaid"
      add :diagram_source, :text, null: false
      add :summary, :text
      add :notes_md, :text

      timestamps()
    end

    create unique_index(:diagrams, [:slug])
    create index(:diagrams, [:concept_id])
    create index(:diagrams, [:document_id])
  end
end
