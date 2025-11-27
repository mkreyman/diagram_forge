defmodule DiagramForge.Content.RateLimiterTest do
  use DiagramForge.DataCase, async: false

  alias DiagramForge.Content.RateLimiter

  # Use unique user/IP IDs per test to avoid conflicts
  defp unique_user_id, do: "test_user_#{System.unique_integer([:positive])}"
  defp unique_ip, do: "192.168.1.#{System.unique_integer([:positive]) |> rem(255)}"

  describe "check_diagram_creation/1" do
    test "allows diagram creation within limits" do
      user_id = unique_user_id()

      assert RateLimiter.check_diagram_creation(user_id) == :ok
    end

    test "rate limits after exceeding minute limit" do
      user_id = unique_user_id()

      # Make 10 requests (the limit)
      for _ <- 1..10 do
        assert RateLimiter.check_diagram_creation(user_id) == :ok
      end

      # 11th request should be rate limited
      assert RateLimiter.check_diagram_creation(user_id) == {:error, :rate_limited}
    end

    test "different users have independent limits" do
      user1 = unique_user_id()
      user2 = unique_user_id()

      # Exhaust user1's limit
      for _ <- 1..10 do
        assert RateLimiter.check_diagram_creation(user1) == :ok
      end

      # user1 is rate limited
      assert RateLimiter.check_diagram_creation(user1) == {:error, :rate_limited}

      # user2 should still be allowed
      assert RateLimiter.check_diagram_creation(user2) == :ok
    end
  end

  describe "check_ip_limit/1" do
    test "allows requests within IP limit" do
      ip = unique_ip()

      assert RateLimiter.check_ip_limit(ip) == :ok
    end

    test "rate limits IP after exceeding limit" do
      ip = unique_ip()

      # Make 5 requests (the limit)
      for _ <- 1..5 do
        assert RateLimiter.check_ip_limit(ip) == :ok
      end

      # 6th request should be rate limited
      assert RateLimiter.check_ip_limit(ip) == {:error, :rate_limited}
    end

    test "different IPs have independent limits" do
      ip1 = unique_ip()
      ip2 = unique_ip()

      # Exhaust ip1's limit
      for _ <- 1..5 do
        assert RateLimiter.check_ip_limit(ip1) == :ok
      end

      # ip1 is rate limited
      assert RateLimiter.check_ip_limit(ip1) == {:error, :rate_limited}

      # ip2 should still be allowed
      assert RateLimiter.check_ip_limit(ip2) == :ok
    end
  end

  describe "check_moderation_submission/1" do
    test "allows moderation submissions within limit" do
      user_id = unique_user_id()

      assert RateLimiter.check_moderation_submission(user_id) == :ok
    end

    test "rate limits after exceeding moderation submission limit" do
      user_id = unique_user_id()

      # Make 5 requests (the limit)
      for _ <- 1..5 do
        assert RateLimiter.check_moderation_submission(user_id) == :ok
      end

      # 6th request should be rate limited
      assert RateLimiter.check_moderation_submission(user_id) == {:error, :rate_limited}
    end
  end

  describe "get_remaining_quota/1" do
    test "returns full quota for new user" do
      user_id = unique_user_id()

      quota = RateLimiter.get_remaining_quota(user_id)

      assert quota.minute == 10
      assert quota.day == 100
    end

    test "decrements quota after usage" do
      user_id = unique_user_id()

      # Use some quota
      for _ <- 1..3 do
        RateLimiter.check_diagram_creation(user_id)
      end

      quota = RateLimiter.get_remaining_quota(user_id)

      assert quota.minute == 7
      # Day quota may also decrement depending on implementation
    end
  end
end
