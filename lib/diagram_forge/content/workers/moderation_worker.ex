defmodule DiagramForge.Content.Workers.ModerationWorker do
  @moduledoc """
  Oban worker that performs AI content moderation on diagrams.

  This job:
  1. Loads the diagram to be moderated
  2. Runs AI moderation analysis
  3. Updates the diagram's moderation status
  4. Creates a moderation log entry

  Jobs are enqueued when a diagram is made public.
  """

  use Oban.Worker, queue: :moderation, max_attempts: 3

  require Logger

  alias DiagramForge.Content
  alias DiagramForge.Content.Moderator
  alias DiagramForge.Diagrams

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"diagram_id" => diagram_id}}) do
    Logger.info("Starting content moderation", diagram_id: diagram_id)

    with {:ok, diagram} <- Diagrams.get_diagram(diagram_id),
         :ok <- validate_needs_moderation(diagram),
         {:ok, result} <- Moderator.moderate(diagram),
         {:ok, _diagram} <- apply_moderation_result(diagram, result) do
      Logger.info("Content moderation completed",
        diagram_id: diagram_id,
        decision: result.decision,
        confidence: result.confidence
      )

      :ok
    else
      {:error, :not_found} ->
        Logger.warning("Diagram not found for moderation", diagram_id: diagram_id)
        :ok

      {:error, :already_moderated} ->
        Logger.info("Diagram already moderated, skipping", diagram_id: diagram_id)
        :ok

      {:error, reason} ->
        Logger.error("Content moderation failed",
          diagram_id: diagram_id,
          reason: inspect(reason)
        )

        # Queue for manual review on persistent failures
        if should_queue_for_review?(reason) do
          Content.update_moderation_status(
            diagram_id,
            :manual_review,
            "Moderation error: #{reason}"
          )
        end

        {:error, reason}
    end
  end

  defp validate_needs_moderation(diagram) do
    cond do
      diagram.moderation_status in [:approved, :rejected] ->
        {:error, :already_moderated}

      diagram.visibility != :public ->
        {:error, :not_public}

      true ->
        :ok
    end
  end

  defp apply_moderation_result(diagram, result) do
    threshold = Moderator.auto_approve_threshold()

    {status, action} =
      case result do
        %{decision: :approve, confidence: c} when c >= threshold ->
          {:approved, "ai_approve"}

        %{decision: :approve} ->
          # Low confidence - queue for manual review
          {:manual_review, "ai_manual_review"}

        %{decision: :reject} ->
          {:rejected, "ai_reject"}

        %{decision: :manual_review} ->
          {:manual_review, "ai_manual_review"}
      end

    Content.update_moderation_status(
      diagram,
      status,
      result.reason,
      ai_result: result,
      action: action
    )
  end

  defp should_queue_for_review?(reason) do
    # Don't queue for transient errors that will be retried
    reason not in [:rate_limit, :timeout, :connection_error]
  end
end
