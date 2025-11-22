defmodule DiagramForge.Repo.Migrations.AddUserIdToDiagrams do
  use Ecto.Migration

  def change do
    alter table(:diagrams) do
      add :user_id, references(:users, type: :binary_id, on_delete: :nilify_all)
      add :created_by_superadmin, :boolean, default: false, null: false
    end

    create index(:diagrams, [:user_id])
    create index(:diagrams, [:created_by_superadmin])
  end
end
