defmodule DiagramForge.AI.Client do
  @moduledoc """
  Thin wrapper around the OpenAI chat completion API with retry logic.

  This module provides automatic retry with exponential backoff for transient
  failures when calling the OpenAI API.
  """

  require Logger

  @behaviour DiagramForge.AI.ClientBehaviour

  alias DiagramForge.ErrorHandling.Retry

  @doc """
  Calls the OpenAI chat completions API with the given messages.

  Automatically retries on transient failures (rate limits, network errors, 5xx).
  Returns the JSON string content from the response.

  ## Options

    * `:model` - Override the default model from config
    * `:max_attempts` - Maximum retry attempts (default: 3)
    * `:base_delay_ms` - Base retry delay in ms (default: 1000)
    * `:max_delay_ms` - Maximum retry delay in ms (default: 10000)
    * `:base_url` - Override the base URL (for testing, default: https://api.openai.com/v1)
    * `:user_id` - User ID for usage tracking
    * `:operation` - Operation type for usage tracking (e.g., "diagram_generation", "syntax_fix")
    * `:track_usage` - Whether to track token usage (default: true)

  ## Examples

      iex> messages = [
      ...>   %{"role" => "system", "content" => "You are a helpful assistant."},
      ...>   %{"role" => "user", "content" => "Hello!"}
      ...> ]
      iex> DiagramForge.AI.Client.chat!(messages)
      "{\"message\": \"Hello! How can I help you today?\"}"

  ## Raises

    * `RuntimeError` - If OPENAI_API_KEY is not configured
    * `RuntimeError` - If request fails after all retries

  """
  def chat!(messages, opts \\ []) do
    {api_key, model, base_url} = get_config(opts)
    retry_opts = build_retry_opts(opts, model, messages)

    case Retry.with_retry(
           fn -> make_request(api_key, model, messages, base_url) end,
           retry_opts
         ) do
      {:ok, content, usage} ->
        # Track usage asynchronously if enabled (default: true)
        if opts[:track_usage] != false do
          track_usage(model, usage, opts)
        end

        content

      {:error, reason} ->
        Logger.error("OpenAI API request failed after retries",
          reason: inspect(reason),
          model: model
        )

        raise "OpenAI API request failed: #{inspect(reason)}"
    end
  end

  defp track_usage(model_api_name, usage, opts) do
    # Track usage asynchronously to avoid blocking the response
    # and to avoid database connection issues in tests
    Task.start(fn ->
      alias DiagramForge.Usage

      # Look up the model by API name to get the model_id
      case Usage.get_model_by_api_name(model_api_name) do
        nil ->
          Logger.warning("Unknown model for usage tracking: #{model_api_name}")

        ai_model ->
          Usage.record_usage(%{
            model_id: ai_model.id,
            user_id: opts[:user_id],
            operation: opts[:operation] || "unknown",
            input_tokens: usage["prompt_tokens"] || 0,
            output_tokens: usage["completion_tokens"] || 0,
            total_tokens: usage["total_tokens"] || 0,
            metadata: %{
              model_api_name: model_api_name
            }
          })
      end
    end)
  end

  # Private functions

  defp get_config(opts) do
    config = Application.get_env(:diagram_forge, DiagramForge.AI, [])
    api_key = opts[:api_key] || config[:api_key] || raise "Missing OPENAI_API_KEY"
    model = opts[:model] || config[:model] || "gpt-4o-mini"
    base_url = opts[:base_url] || "https://api.openai.com/v1"
    {api_key, model, base_url}
  end

  defp build_retry_opts(opts, model, messages) do
    [
      max_attempts: opts[:max_attempts] || 3,
      base_delay_ms: opts[:base_delay_ms] || 1000,
      max_delay_ms: opts[:max_delay_ms] || 10_000,
      context: %{
        operation: "openai_chat_completion",
        model: model,
        message_count: length(messages)
      }
    ]
  end

  defp make_request(api_key, model, messages, base_url) do
    body = %{
      "model" => model,
      "messages" => messages,
      "response_format" => %{"type" => "json_object"}
    }

    url = "#{base_url}/chat/completions"

    case Req.post(url,
           json: body,
           headers: [
             {"authorization", "Bearer #{api_key}"},
             {"content-type", "application/json"}
           ]
         ) do
      {:ok, %{status: status} = resp} when status >= 200 and status < 300 ->
        # Parse and log rate limit headers
        parse_rate_limit_headers(resp.headers)

        content =
          resp.body["choices"]
          |> List.first()
          |> get_in(["message", "content"])

        usage = resp.body["usage"] || %{}

        {:ok, content, usage}

      {:ok, %{status: status} = resp} ->
        # Also parse rate limits on error responses
        parse_rate_limit_headers(resp.headers)

        {:error, %{status: status, body: resp.body}}

      {:error, _reason} = error ->
        error
    end
  end

  defp parse_rate_limit_headers(headers) do
    rate_limit_info = %{
      requests_limit: get_header_value(headers, "x-ratelimit-limit-requests"),
      requests_remaining: get_header_value(headers, "x-ratelimit-remaining-requests"),
      requests_reset: get_header_value(headers, "x-ratelimit-reset-requests"),
      tokens_limit: get_header_value(headers, "x-ratelimit-limit-tokens"),
      tokens_remaining: get_header_value(headers, "x-ratelimit-remaining-tokens"),
      tokens_reset: get_header_value(headers, "x-ratelimit-reset-tokens")
    }

    # Log warnings when approaching rate limits
    check_rate_limit_threshold(rate_limit_info)

    rate_limit_info
  end

  defp get_header_value(headers, key) when is_map(headers) do
    case Map.get(headers, key) do
      [value | _] when is_binary(value) -> parse_header_value(value)
      value when is_binary(value) -> parse_header_value(value)
      _ -> nil
    end
  end

  defp parse_header_value(value) when is_binary(value) do
    case Integer.parse(value) do
      {int, _} -> int
      :error -> value
    end
  end

  defp check_rate_limit_threshold(rate_limit_info) do
    # Check request rate limits
    check_threshold(
      rate_limit_info.requests_remaining,
      rate_limit_info.requests_limit,
      "requests",
      rate_limit_info.requests_reset
    )

    # Check token rate limits
    check_threshold(
      rate_limit_info.tokens_remaining,
      rate_limit_info.tokens_limit,
      "tokens",
      rate_limit_info.tokens_reset
    )
  end

  defp check_threshold(nil, _limit, _type, _reset), do: :ok
  defp check_threshold(_remaining, nil, _type, _reset), do: :ok

  defp check_threshold(remaining, limit, type, reset)
       when is_integer(remaining) and is_integer(limit) do
    percentage = remaining / limit * 100

    cond do
      # Less than 10% remaining - critical warning
      percentage < 10 ->
        Logger.warning(
          "OpenAI rate limit critical: #{type} - #{remaining}/#{limit} (#{Float.round(percentage, 1)}%), reset: #{format_reset_time(reset)}"
        )

      # Less than 25% remaining - warning
      percentage < 25 ->
        Logger.warning(
          "OpenAI rate limit approaching: #{type} - #{remaining}/#{limit} (#{Float.round(percentage, 1)}%), reset: #{format_reset_time(reset)}"
        )

      # Log at debug level when above 25%
      true ->
        Logger.debug(
          "OpenAI rate limit status: #{type} - #{remaining}/#{limit} (#{Float.round(percentage, 1)}%)"
        )
    end
  end

  defp check_threshold(_remaining, _limit, _type, _reset), do: :ok

  defp format_reset_time(nil), do: "unknown"

  defp format_reset_time(reset) when is_binary(reset) do
    case DateTime.from_iso8601(reset) do
      {:ok, dt, _offset} ->
        seconds_until_reset = DateTime.diff(dt, DateTime.utc_now())
        "#{seconds_until_reset}s"

      {:error, _} ->
        reset
    end
  end

  defp format_reset_time(reset) when is_integer(reset) do
    "#{reset}s"
  end
end
