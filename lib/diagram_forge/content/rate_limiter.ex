defmodule DiagramForge.Content.RateLimiter do
  @moduledoc """
  Rate limiting for content creation to prevent abuse.

  Uses Hammer for efficient rate limiting with ETS backend.

  ## Limits

  - Per user: 10 public diagrams per minute, 100 per day
  - Per IP (unauthenticated): 5 diagrams per minute

  ## Usage

      case RateLimiter.check_diagram_creation(user_id) do
        :ok -> proceed_with_creation()
        {:error, :rate_limited} -> show_rate_limit_error()
      end
  """

  @type limit_result :: :ok | {:error, :rate_limited}

  # Per-user limits for public diagram creation
  @user_minute_limit 10
  @user_minute_scale 60_000
  @user_day_limit 100
  @user_day_scale 86_400_000

  # Per-IP limits for unauthenticated requests
  @ip_minute_limit 5
  @ip_minute_scale 60_000

  @doc """
  Checks if a user can create a public diagram.

  Returns `:ok` if allowed, `{:error, :rate_limited}` if rate limited.
  """
  @spec check_diagram_creation(String.t()) :: limit_result()
  def check_diagram_creation(user_id) when is_binary(user_id) do
    minute_key = "diagram_create:user:minute:#{user_id}"
    day_key = "diagram_create:user:day:#{user_id}"

    with {:allow, _} <- Hammer.check_rate(minute_key, @user_minute_scale, @user_minute_limit),
         {:allow, _} <- Hammer.check_rate(day_key, @user_day_scale, @user_day_limit) do
      :ok
    else
      {:deny, _} -> {:error, :rate_limited}
    end
  end

  @doc """
  Checks if an IP can create content (for unauthenticated requests).

  Returns `:ok` if allowed, `{:error, :rate_limited}` if rate limited.
  """
  @spec check_ip_limit(String.t()) :: limit_result()
  def check_ip_limit(ip_address) when is_binary(ip_address) do
    key = "diagram_create:ip:minute:#{ip_address}"

    case Hammer.check_rate(key, @ip_minute_scale, @ip_minute_limit) do
      {:allow, _} -> :ok
      {:deny, _} -> {:error, :rate_limited}
    end
  end

  @doc """
  Checks rate limits for moderation operations.

  Prevents abuse of the moderation system (e.g., repeatedly editing
  rejected diagrams to get past moderation).
  """
  @spec check_moderation_submission(String.t()) :: limit_result()
  def check_moderation_submission(user_id) when is_binary(user_id) do
    # 5 moderation submissions per minute per user
    key = "moderation_submit:user:minute:#{user_id}"

    case Hammer.check_rate(key, 60_000, 5) do
      {:allow, _} -> :ok
      {:deny, _} -> {:error, :rate_limited}
    end
  end

  @doc """
  Gets remaining quota for a user's diagram creation.

  Returns a map with minute and day remaining counts.
  """
  @spec get_remaining_quota(String.t()) :: %{minute: non_neg_integer(), day: non_neg_integer()}
  def get_remaining_quota(user_id) when is_binary(user_id) do
    minute_key = "diagram_create:user:minute:#{user_id}"
    day_key = "diagram_create:user:day:#{user_id}"

    minute_remaining =
      case Hammer.inspect_bucket(minute_key, @user_minute_scale, @user_minute_limit) do
        {:ok, {_count, remaining, _ms_to_next, _created, _updated}} -> remaining
        {:error, _} -> @user_minute_limit
      end

    day_remaining =
      case Hammer.inspect_bucket(day_key, @user_day_scale, @user_day_limit) do
        {:ok, {_count, remaining, _ms_to_next, _created, _updated}} -> remaining
        {:error, _} -> @user_day_limit
      end

    %{minute: minute_remaining, day: day_remaining}
  end
end
