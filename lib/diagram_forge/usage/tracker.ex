defmodule DiagramForge.Usage.Tracker do
  @moduledoc """
  Default implementation of usage tracking.

  This module handles tracking token usage for AI model requests.
  Usage is recorded asynchronously via a Task to avoid blocking
  the response path.

  ## Validation

  The tracker validates that `user_id` is present in options. If `user_id`
  is nil, a warning is logged and the usage is still recorded (for audit
  purposes) but cannot be attributed to a specific user.

  Callers should use `DiagramForge.AI.Options` to validate options before
  reaching this point - the tracker validation is a defense-in-depth measure.
  """

  @behaviour DiagramForge.Usage.TrackerBehaviour

  require Logger

  alias DiagramForge.Usage

  @impl true
  def track_usage(model_api_name, usage, opts) do
    # Track usage asynchronously to avoid blocking the response
    Task.start(fn ->
      do_track_usage(model_api_name, usage, opts)
    end)

    :ok
  end

  @doc """
  Synchronous version of track_usage for use in tests or when
  async behavior is not desired.
  """
  def track_usage_sync(model_api_name, usage, opts) do
    do_track_usage(model_api_name, usage, opts)
    :ok
  end

  defp do_track_usage(model_api_name, usage, opts) do
    user_id = opts[:user_id]
    operation = opts[:operation] || "unknown"

    # Defense-in-depth: warn if user_id is missing
    # This should be caught earlier by AI.Options validation, but we log here
    # as a safety net to make silent failures visible
    if is_nil(user_id) do
      Logger.warning(
        "Usage tracking called without user_id - usage cannot be attributed to a user. " <>
          "Model: #{model_api_name}, Operation: #{operation}"
      )
    end

    # Look up the model by API name to get the model_id
    case Usage.get_model_by_api_name(model_api_name) do
      nil ->
        Logger.warning("Unknown model for usage tracking: #{model_api_name}")

      ai_model ->
        Usage.record_usage(%{
          model_id: ai_model.id,
          user_id: user_id,
          operation: operation,
          input_tokens: usage["prompt_tokens"] || 0,
          output_tokens: usage["completion_tokens"] || 0,
          total_tokens: usage["total_tokens"] || 0,
          metadata: %{
            model_api_name: model_api_name
          }
        })
    end
  end
end
