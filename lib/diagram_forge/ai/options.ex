defmodule DiagramForge.AI.Options do
  @moduledoc """
  Validated options for AI client calls.

  This module enforces that critical options like `user_id` are explicitly
  provided, preventing silent failures in usage tracking.

  ## Usage

      # For authenticated users - user_id required
      {:ok, opts} = Options.new(user_id: user.id, operation: "diagram_generation")

      # For system operations without user context
      {:ok, opts} = Options.new(user_id: nil, operation: "system_task", track_usage: false)

      # Missing required options - raises error
      {:error, reason} = Options.new(operation: "diagram_generation")

  ## Design Rationale

  This module exists to prevent a class of bugs where optional keyword list
  parameters silently fail to propagate through call chains. By requiring
  explicit construction with validation, we ensure that:

  1. Callers must explicitly decide about user_id (even if nil)
  2. Usage tracking is explicitly enabled/disabled
  3. Missing critical options fail fast at the call site, not deep in the stack
  """

  @type t :: %__MODULE__{
          user_id: String.t() | nil,
          operation: String.t(),
          track_usage: boolean(),
          ai_client: module() | nil
        }

  @enforce_keys [:operation]
  defstruct [
    :user_id,
    :operation,
    :ai_client,
    track_usage: true
  ]

  @valid_operations ~w(diagram_generation syntax_fix)

  @doc """
  Creates validated AI options from a keyword list.

  Returns `{:ok, %Options{}}` on success or `{:error, reason}` on validation failure.

  ## Required Options

  - `:operation` - The operation type (e.g., "diagram_generation", "syntax_fix")

  ## Conditional Requirements

  - `:user_id` - Required when `:track_usage` is true (default)

  ## Optional

  - `:track_usage` - Whether to track token usage (default: true)
  - `:ai_client` - Override the AI client module (for testing)

  ## Examples

      iex> Options.new(user_id: "123", operation: "diagram_generation")
      {:ok, %Options{user_id: "123", operation: "diagram_generation", track_usage: true}}

      iex> Options.new(operation: "diagram_generation")
      {:error, "user_id is required when track_usage is enabled"}

      iex> Options.new(operation: "diagram_generation", track_usage: false)
      {:ok, %Options{user_id: nil, operation: "diagram_generation", track_usage: false}}
  """
  @spec new(keyword()) :: {:ok, t()} | {:error, String.t()}
  def new(opts) when is_list(opts) do
    with {:ok, operation} <- validate_operation(opts),
         {:ok, user_id, track_usage} <- validate_user_tracking(opts) do
      {:ok,
       %__MODULE__{
         user_id: user_id,
         operation: operation,
         track_usage: track_usage,
         ai_client: opts[:ai_client]
       }}
    end
  end

  @doc """
  Creates validated AI options, raising on failure.

  Same as `new/1` but raises `ArgumentError` on validation failure.
  Use this when you're certain the options should be valid.

  ## Examples

      iex> Options.new!(user_id: "123", operation: "diagram_generation")
      %Options{user_id: "123", operation: "diagram_generation", track_usage: true}

      iex> Options.new!(operation: "diagram_generation")
      ** (ArgumentError) user_id is required when track_usage is enabled
  """
  @spec new!(keyword()) :: t()
  def new!(opts) when is_list(opts) do
    case new(opts) do
      {:ok, options} -> options
      {:error, reason} -> raise ArgumentError, reason
    end
  end

  @doc """
  Converts options to a keyword list for passing to AI client.

  This is useful when interfacing with code that expects keyword lists.
  """
  @spec to_keyword_list(t()) :: keyword()
  def to_keyword_list(%__MODULE__{} = opts) do
    [
      user_id: opts.user_id,
      operation: opts.operation,
      track_usage: opts.track_usage
    ]
    |> maybe_add_ai_client(opts.ai_client)
  end

  defp maybe_add_ai_client(keyword_list, nil), do: keyword_list
  defp maybe_add_ai_client(keyword_list, ai_client), do: [{:ai_client, ai_client} | keyword_list]

  defp validate_operation(opts) do
    case Keyword.get(opts, :operation) do
      nil ->
        {:error, "operation is required"}

      operation when operation in @valid_operations ->
        {:ok, operation}

      operation ->
        {:error,
         "invalid operation '#{operation}', must be one of: #{Enum.join(@valid_operations, ", ")}"}
    end
  end

  defp validate_user_tracking(opts) do
    user_id = Keyword.get(opts, :user_id)
    track_usage = Keyword.get(opts, :track_usage, true)

    if track_usage && is_nil(user_id) do
      {:error, "user_id is required when track_usage is enabled"}
    else
      {:ok, user_id, track_usage}
    end
  end
end
