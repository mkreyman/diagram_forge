defmodule DiagramForge.Repo.Migrations.CreateSavedFilters do
  use Ecto.Migration

  def change do
    create table(:saved_filters, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id, references(:users, type: :binary_id, on_delete: :delete_all), null: false

      add :name, :string, null: false
      add :tag_filter, {:array, :string}, null: false, default: []
      add :is_pinned, :boolean, null: false, default: true
      add :sort_order, :integer, null: false, default: 0

      timestamps()
    end

    # Efficient queries for user's filters
    create index(:saved_filters, [:user_id])

    # Efficient queries for pinned filters
    create index(:saved_filters, [:user_id, :is_pinned])

    # Efficient queries for ordering pinned filters
    create index(:saved_filters, [:user_id, :sort_order])

    # Prevent duplicate filter names per user
    create unique_index(:saved_filters, [:user_id, :name])
  end
end
