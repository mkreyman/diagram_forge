defmodule DiagramForge.Repo.Migrations.CreatePrompts do
  use Ecto.Migration

  def change do
    create table(:prompts, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :key, :string, null: false
      add :content, :text, null: false
      add :description, :string

      timestamps()
    end

    create unique_index(:prompts, [:key])
  end
end
