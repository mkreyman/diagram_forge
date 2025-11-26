defmodule DiagramForge.Repo.Migrations.CreateDiagrams do
  use Ecto.Migration

  def change do
    create table(:diagrams, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :document_id, references(:documents, type: :binary_id, on_delete: :nilify_all)
      add :forked_from_id, references(:diagrams, type: :binary_id, on_delete: :nilify_all)
      add :title, :string, null: false
      add :tags, {:array, :string}, default: []
      add :format, :string, null: false, default: "mermaid"
      add :diagram_source, :text, null: false
      add :summary, :text
      add :notes_md, :text
      add :visibility, :string, null: false, default: "unlisted"

      timestamps()
    end

    create index(:diagrams, [:document_id])
    create index(:diagrams, [:forked_from_id])
    create index(:diagrams, [:visibility])
    # GIN index for efficient tag queries
    create index(:diagrams, [:tags], using: :gin)
  end
end
