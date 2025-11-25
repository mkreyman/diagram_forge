defmodule DiagramForge.AI.ClientBehaviour do
  @moduledoc """
  Behaviour definition for AI client implementations.

  This behaviour defines the contract for AI clients that interact with
  language models (OpenAI, Anthropic, etc.). Implementations must handle
  message formatting, API communication, and usage tracking.

  ## Required Options

  All implementations must respect these options:

  - `:user_id` - **Required when `:track_usage` is true**. The ID of the user
    making the request. Used for per-user usage tracking and cost attribution.
    If usage tracking is disabled, this can be nil.

  - `:operation` - **Required**. The type of operation being performed.
    Valid values: `"diagram_generation"`, `"syntax_fix"`.
    Used for categorizing usage in reports.

  ## Optional Options

  - `:track_usage` - Whether to track token usage (default: `true`).
    Set to `false` for system operations or testing where tracking is not needed.

  - `:model` - Override the default model for this request.

  ## Usage Tracking Contract

  When `track_usage` is `true` (the default), implementations MUST:

  1. Extract usage data from the API response
  2. Call the usage tracker with `user_id`, `operation`, and token counts
  3. Log a warning if usage data is missing from the response

  When `track_usage` is `false`, implementations SHOULD NOT call the usage tracker.

  ## Testing

  Use `Mox` to mock this behaviour in tests. **Important**: Test mocks should
  verify that required options are passed. See `DiagramForge.AI.Options` for
  validation helpers.

  ## Example Implementation

      def chat!(messages, opts) do
        # Validate options early
        user_id = Keyword.fetch!(opts, :user_id)
        operation = Keyword.fetch!(opts, :operation)
        track_usage = Keyword.get(opts, :track_usage, true)

        # Make API call...
        {content, usage} = call_api(messages)

        # Track usage if enabled
        if track_usage do
          usage_tracker().track_usage(model, usage, opts)
        end

        content
      end
  """

  @type message :: %{String.t() => String.t()}

  @type options :: [
          user_id: String.t() | nil,
          operation: String.t(),
          track_usage: boolean(),
          model: String.t()
        ]

  @doc """
  Sends messages to the AI model and returns the response content.

  ## Parameters

  - `messages` - List of message maps with "role" and "content" keys
  - `opts` - Options keyword list (see module documentation for required/optional options)

  ## Returns

  The content string from the AI model response.

  ## Raises

  - Various errors on API failure (implementation-specific)
  - Should raise on missing required options when track_usage is enabled
  """
  @callback chat!([message()], options()) :: String.t()
end
