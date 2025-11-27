defmodule DiagramForge.Content.ModerationLog do
  @moduledoc """
  Schema for tracking all moderation actions taken on diagrams.

  This provides an audit trail of both AI-driven and human moderation
  decisions for accountability and debugging purposes.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "moderation_logs" do
    belongs_to :diagram, DiagramForge.Diagrams.Diagram
    belongs_to :performed_by, DiagramForge.Accounts.User

    # ai_approve, ai_reject, ai_manual_review, admin_approve, admin_reject
    field :action, :string
    field :previous_status, :string
    field :new_status, :string
    field :reason, :string

    # AI-specific fields
    field :ai_confidence, :decimal
    field :ai_flags, {:array, :string}, default: []

    timestamps(updated_at: false)
  end

  @valid_actions ~w(ai_approve ai_reject ai_manual_review admin_approve admin_reject)
  @valid_statuses ~w(pending approved rejected manual_review)

  def changeset(log, attrs) do
    log
    |> cast(attrs, [
      :diagram_id,
      :performed_by_id,
      :action,
      :previous_status,
      :new_status,
      :reason,
      :ai_confidence,
      :ai_flags
    ])
    |> validate_required([:diagram_id, :action, :new_status])
    |> validate_inclusion(:action, @valid_actions)
    |> validate_inclusion(:new_status, @valid_statuses)
    |> validate_number(:ai_confidence, greater_than_or_equal_to: 0, less_than_or_equal_to: 1)
    |> foreign_key_constraint(:diagram_id)
    |> foreign_key_constraint(:performed_by_id)
  end

  @doc """
  Creates a changeset for an AI moderation action.
  """
  def ai_changeset(log, attrs) do
    log
    |> changeset(attrs)
    |> validate_required([:ai_confidence])
  end

  @doc """
  Creates a changeset for an admin moderation action.
  """
  def admin_changeset(log, attrs) do
    log
    |> changeset(attrs)
    |> validate_required([:performed_by_id, :reason])
  end
end
