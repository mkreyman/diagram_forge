defmodule DiagramForge.Content do
  @moduledoc """
  The Content context - handles content moderation and sanitization.

  This module provides:
  - Content sanitization (HTML stripping, URL removal)
  - AI-powered content moderation
  - Moderation workflow management
  - Admin moderation actions
  """

  import Ecto.Query

  alias DiagramForge.Content.MermaidSanitizer
  alias DiagramForge.Content.ModerationLog
  alias DiagramForge.Content.Sanitizer
  alias DiagramForge.Content.Workers.ModerationWorker
  alias DiagramForge.Diagrams.Diagram
  alias DiagramForge.Repo

  # =============================================================================
  # Sanitization
  # =============================================================================

  @doc """
  Sanitizes diagram content before saving.
  Applies HTML stripping and URL removal based on configuration.
  """
  def sanitize_diagram_content(attrs) when is_map(attrs) do
    attrs
    |> sanitize_field(:title)
    |> sanitize_field(:summary)
    |> sanitize_mermaid_source()
  end

  defp sanitize_field(attrs, field) do
    case Map.get(attrs, field) || Map.get(attrs, to_string(field)) do
      nil -> attrs
      value -> Map.put(attrs, field, Sanitizer.sanitize_field(value))
    end
  end

  defp sanitize_mermaid_source(attrs) do
    source = Map.get(attrs, :diagram_source) || Map.get(attrs, "diagram_source")

    if source do
      sanitized = MermaidSanitizer.sanitize(source)
      Map.put(attrs, :diagram_source, sanitized)
    else
      attrs
    end
  end

  # =============================================================================
  # Moderation Workflow
  # =============================================================================

  @doc """
  Enqueues a diagram for content moderation.
  Should be called when a diagram is made public.
  """
  def enqueue_moderation(%Diagram{} = diagram) do
    if moderation_enabled?() and Diagram.requires_moderation?(diagram) do
      %{diagram_id: diagram.id}
      |> ModerationWorker.new()
      |> Oban.insert()
    else
      {:ok, :skipped}
    end
  end

  @doc """
  Updates a diagram's moderation status and creates a log entry.

  ## Options

    * `:ai_result` - The AI moderation result (for AI actions)
    * `:action` - The action type (ai_approve, admin_approve, etc.)
    * `:performed_by_id` - User ID for admin actions
  """
  def update_moderation_status(diagram_or_id, status, reason, opts \\ [])

  def update_moderation_status(diagram_id, status, reason, opts) when is_binary(diagram_id) do
    case Repo.get(Diagram, diagram_id) do
      nil -> {:error, :not_found}
      diagram -> update_moderation_status(diagram, status, reason, opts)
    end
  end

  def update_moderation_status(%Diagram{} = diagram, status, reason, opts) do
    Repo.transaction(fn ->
      # Update diagram
      changeset =
        Diagram.moderation_changeset(diagram, %{
          moderation_status: status,
          moderation_reason: reason,
          moderated_at: DateTime.utc_now() |> DateTime.truncate(:second),
          moderated_by_id: opts[:performed_by_id]
        })

      case Repo.update(changeset) do
        {:ok, updated_diagram} ->
          # Create log entry
          create_moderation_log(diagram, status, reason, opts)
          updated_diagram

        {:error, changeset} ->
          Repo.rollback(changeset)
      end
    end)
  end

  defp create_moderation_log(diagram, new_status, reason, opts) do
    ai_result = opts[:ai_result]
    action = opts[:action] || infer_action(opts[:performed_by_id], new_status)

    attrs = %{
      diagram_id: diagram.id,
      action: action,
      previous_status: to_string(diagram.moderation_status),
      new_status: to_string(new_status),
      reason: reason,
      performed_by_id: opts[:performed_by_id],
      ai_confidence: ai_result[:confidence],
      ai_flags: ai_result[:flags] || []
    }

    %ModerationLog{}
    |> ModerationLog.changeset(attrs)
    |> Repo.insert!()
  end

  defp infer_action(nil, :approved), do: "ai_approve"
  defp infer_action(nil, :rejected), do: "ai_reject"
  defp infer_action(nil, :manual_review), do: "ai_manual_review"
  defp infer_action(_user_id, :approved), do: "admin_approve"
  defp infer_action(_user_id, :rejected), do: "admin_reject"
  defp infer_action(_user_id, _status), do: "admin_action"

  # =============================================================================
  # Admin Actions
  # =============================================================================

  @doc """
  Admin approves a diagram that was pending review.
  """
  def admin_approve(%Diagram{} = diagram, admin_user_id, reason \\ "Manually approved") do
    update_moderation_status(diagram, :approved, reason,
      performed_by_id: admin_user_id,
      action: "admin_approve"
    )
  end

  @doc """
  Admin rejects a diagram.
  The diagram will be made private automatically.
  """
  def admin_reject(%Diagram{} = diagram, admin_user_id, reason) do
    Repo.transaction(fn ->
      # Update moderation status
      case update_moderation_status(diagram, :rejected, reason,
             performed_by_id: admin_user_id,
             action: "admin_reject"
           ) do
        {:ok, updated_diagram} ->
          # Make diagram private
          updated_diagram
          |> Diagram.changeset(%{visibility: :private})
          |> Repo.update!()

        {:error, changeset} ->
          Repo.rollback(changeset)
      end
    end)
  end

  # =============================================================================
  # Queries
  # =============================================================================

  @doc """
  Lists diagrams pending manual review.
  """
  def list_pending_review(opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)

    Diagram
    |> where([d], d.moderation_status == :manual_review)
    |> order_by([d], desc: d.inserted_at)
    |> limit(^limit)
    |> Repo.all()
  end

  @doc """
  Gets moderation statistics for all diagrams.
  """
  def get_moderation_stats do
    query =
      from d in Diagram,
        group_by: d.moderation_status,
        select: {d.moderation_status, count(d.id)}

    stats = Repo.all(query) |> Map.new()

    %{
      pending: Map.get(stats, :pending, 0),
      approved: Map.get(stats, :approved, 0),
      rejected: Map.get(stats, :rejected, 0),
      manual_review: Map.get(stats, :manual_review, 0)
    }
  end

  @doc """
  Lists moderation logs for a diagram.
  """
  def list_moderation_logs(diagram_id) do
    ModerationLog
    |> where([l], l.diagram_id == ^diagram_id)
    |> order_by([l], desc: l.inserted_at, desc: l.id)
    |> Repo.all()
  end

  # =============================================================================
  # Configuration
  # =============================================================================

  @doc """
  Checks if content moderation is enabled.
  """
  def moderation_enabled? do
    Application.get_env(:diagram_forge, __MODULE__, [])
    |> Keyword.get(:moderation_enabled, true)
  end
end
