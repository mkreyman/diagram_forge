defmodule DiagramForge.Repo.Migrations.CreateModerationLogs do
  use Ecto.Migration

  def change do
    create table(:moderation_logs, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :diagram_id, references(:diagrams, type: :binary_id, on_delete: :delete_all),
        null: false

      add :performed_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)

      # ai_approve, ai_reject, ai_manual_review, admin_approve, admin_reject
      add :action, :string, null: false
      add :previous_status, :string
      add :new_status, :string, null: false
      add :reason, :text

      # AI-specific fields
      add :ai_confidence, :decimal, precision: 3, scale: 2
      add :ai_flags, {:array, :string}, default: []

      timestamps(updated_at: false)
    end

    create index(:moderation_logs, [:diagram_id])
    create index(:moderation_logs, [:action])
    create index(:moderation_logs, [:inserted_at])
  end
end
