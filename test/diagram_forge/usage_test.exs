defmodule DiagramForge.UsageTest do
  use DiagramForge.DataCase, async: true

  alias DiagramForge.Usage
  alias DiagramForge.Usage.DailyAggregate

  describe "cost calculation" do
    test "calculate_cost/3 calculates cost in cents from tokens and price struct" do
      provider = fixture(:ai_provider)
      model = fixture(:ai_model, provider: provider)

      # $1.00 per million input, $2.00 per million output
      price =
        fixture(:ai_model_price,
          model: model,
          input_price_per_million: Decimal.new("1.00"),
          output_price_per_million: Decimal.new("2.00")
        )

      input_tokens = 1_000_000
      output_tokens = 500_000

      # Expected: (1M * $1.00 / 1M) + (500K * $2.00 / 1M) = $1.00 + $1.00 = $2.00 = 200 cents
      cost_cents = Usage.calculate_cost(input_tokens, output_tokens, price)

      assert cost_cents == 200
    end

    test "calculate_cost/3 handles small token counts" do
      provider = fixture(:ai_provider)
      model = fixture(:ai_model, provider: provider)

      price =
        fixture(:ai_model_price,
          model: model,
          input_price_per_million: Decimal.new("3.00"),
          output_price_per_million: Decimal.new("15.00")
        )

      input_tokens = 1000
      output_tokens = 500

      # Expected: (1000 * $3.00 / 1M) + (500 * $15.00 / 1M) = $0.003 + $0.0075 = $0.0105 = ~1 cent
      cost_cents = Usage.calculate_cost(input_tokens, output_tokens, price)

      # Should round to 1 cent
      assert cost_cents == 1
    end

    test "calculate_cost/3 handles zero tokens" do
      provider = fixture(:ai_provider)
      model = fixture(:ai_model, provider: provider)

      price =
        fixture(:ai_model_price,
          model: model,
          input_price_per_million: Decimal.new("1.00"),
          output_price_per_million: Decimal.new("2.00")
        )

      cost_cents = Usage.calculate_cost(0, 0, price)

      assert cost_cents == 0
    end

    test "calculate_cost/3 returns nil when price is nil" do
      assert Usage.calculate_cost(1000, 500, nil) == nil
    end
  end

  describe "record_usage/1" do
    test "creates token usage record and updates daily aggregation" do
      provider = fixture(:ai_provider)
      model = fixture(:ai_model, provider: provider)

      _price =
        fixture(:ai_model_price,
          model: model,
          input_price_per_million: Decimal.new("1.00"),
          output_price_per_million: Decimal.new("2.00")
        )

      user = fixture(:user)

      attrs = %{
        user_id: user.id,
        model_id: model.id,
        operation: "diagram_generation",
        input_tokens: 10_000,
        output_tokens: 5_000,
        total_tokens: 15_000,
        metadata: %{"source" => "test"}
      }

      assert {:ok, token_usage} = Usage.record_usage(attrs)
      assert token_usage.input_tokens == 10_000
      assert token_usage.output_tokens == 5_000
      assert token_usage.user_id == user.id
      assert token_usage.model_id == model.id
      # Cost should be calculated: (10K * $1 / 1M) + (5K * $2 / 1M) = $0.01 + $0.01 = 2 cents
      assert token_usage.cost_cents == 2

      # Verify daily usage was aggregated
      daily =
        Repo.get_by(DailyAggregate, user_id: user.id, model_id: model.id, date: Date.utc_today())

      assert daily != nil
      assert daily.input_tokens == 10_000
      assert daily.output_tokens == 5_000
      assert daily.cost_cents == 2
      assert daily.request_count == 1
    end

    test "accumulates daily usage on multiple records same day" do
      provider = fixture(:ai_provider)
      model = fixture(:ai_model, provider: provider)

      _price =
        fixture(:ai_model_price,
          model: model,
          input_price_per_million: Decimal.new("1.00"),
          output_price_per_million: Decimal.new("2.00")
        )

      user = fixture(:user)

      attrs1 = %{
        user_id: user.id,
        model_id: model.id,
        operation: "diagram_generation",
        input_tokens: 1000,
        output_tokens: 500,
        total_tokens: 1500,
        metadata: %{}
      }

      attrs2 = %{
        user_id: user.id,
        model_id: model.id,
        operation: "diagram_generation",
        input_tokens: 2000,
        output_tokens: 1000,
        total_tokens: 3000,
        metadata: %{}
      }

      {:ok, _} = Usage.record_usage(attrs1)
      {:ok, _} = Usage.record_usage(attrs2)

      daily =
        Repo.get_by(DailyAggregate, user_id: user.id, model_id: model.id, date: Date.utc_today())

      assert daily.input_tokens == 3000
      assert daily.output_tokens == 1500
      assert daily.request_count == 2
    end
  end

  describe "get_monthly_summary/2" do
    test "returns aggregated stats for the month" do
      provider = fixture(:ai_provider)
      model = fixture(:ai_model, provider: provider)
      user = fixture(:user)

      # $1.00 per million input, $2.00 per million output
      _price =
        fixture(:ai_model_price,
          model: model,
          input_price_per_million: Decimal.new("1.00"),
          output_price_per_million: Decimal.new("2.00")
        )

      today = Date.utc_today()

      # Create daily aggregates for current month
      # With pricing: (10K * $1 / 1M) + (5K * $2 / 1M) = $0.01 + $0.01 = 2 cents
      fixture(:daily_aggregate,
        user: user,
        model: model,
        date: today,
        input_tokens: 10_000,
        output_tokens: 5_000,
        total_tokens: 15_000,
        cost_cents: 2,
        request_count: 5
      )

      # Only add another day if we're not on the first day of the month
      if today.day > 1 do
        # With pricing: (20K * $1 / 1M) + (10K * $2 / 1M) = $0.02 + $0.02 = 4 cents
        fixture(:daily_aggregate,
          user: user,
          model: model,
          date: Date.add(today, -1),
          input_tokens: 20_000,
          output_tokens: 10_000,
          total_tokens: 30_000,
          cost_cents: 4,
          request_count: 10
        )

        summary = Usage.get_monthly_summary(today.year, today.month)

        assert summary.input_tokens == 30_000
        assert summary.output_tokens == 15_000
        # Cost calculated from tokens: 2 + 4 = 6 cents
        assert summary.cost_cents == 6
        assert summary.request_count == 15
      else
        summary = Usage.get_monthly_summary(today.year, today.month)

        assert summary.input_tokens == 10_000
        assert summary.output_tokens == 5_000
        # Cost calculated from tokens: 2 cents
        assert summary.cost_cents == 2
        assert summary.request_count == 5
      end
    end

    test "returns zeros when no usage exists" do
      summary = Usage.get_monthly_summary(2020, 1)

      assert summary.input_tokens == 0
      assert summary.output_tokens == 0
      assert summary.cost_cents == 0
      assert summary.request_count == 0
    end
  end

  describe "get_daily_costs/2" do
    test "returns daily costs for the month" do
      provider = fixture(:ai_provider)
      model = fixture(:ai_model, provider: provider)
      user = fixture(:user)

      # $1.00 per million input, $2.00 per million output
      _price =
        fixture(:ai_model_price,
          model: model,
          input_price_per_million: Decimal.new("1.00"),
          output_price_per_million: Decimal.new("2.00")
        )

      today = Date.utc_today()
      start_of_month = Date.beginning_of_month(today)

      # With pricing: (100K * $1 / 1M) + (50K * $2 / 1M) = $0.10 + $0.10 = 20 cents
      fixture(:daily_aggregate,
        user: user,
        model: model,
        date: start_of_month,
        input_tokens: 100_000,
        output_tokens: 50_000,
        cost_cents: 20,
        request_count: 5
      )

      # Only add second day if it exists in the month range
      second_day = Date.add(start_of_month, 1)

      if Date.compare(second_day, Date.end_of_month(start_of_month)) != :gt do
        fixture(:daily_aggregate,
          user: user,
          model: model,
          date: second_day,
          input_tokens: 200_000,
          output_tokens: 100_000,
          cost_cents: 40,
          request_count: 10
        )
      end

      daily_costs = Usage.get_daily_costs(today.year, today.month)

      # First day should have cost calculated from tokens
      first_day_cost = Enum.find(daily_costs, &(&1.date == start_of_month))
      assert first_day_cost.cost_cents == 20
    end
  end

  describe "get_top_users_by_cost/2" do
    test "returns top users ordered by cost" do
      provider = fixture(:ai_provider)
      model = fixture(:ai_model, provider: provider)
      user1 = fixture(:user)
      user2 = fixture(:user)

      # $1.00 per million input, $2.00 per million output
      _price =
        fixture(:ai_model_price,
          model: model,
          input_price_per_million: Decimal.new("1.00"),
          output_price_per_million: Decimal.new("2.00")
        )

      today = Date.utc_today()

      # User 1 has less cost: (100K * $1 / 1M) + (50K * $2 / 1M) = 20 cents
      fixture(:daily_aggregate,
        user: user1,
        model: model,
        date: today,
        input_tokens: 100_000,
        output_tokens: 50_000,
        cost_cents: 20
      )

      # User 2 has more cost: (500K * $1 / 1M) + (250K * $2 / 1M) = 100 cents
      fixture(:daily_aggregate,
        user: user2,
        model: model,
        date: today,
        input_tokens: 500_000,
        output_tokens: 250_000,
        cost_cents: 100
      )

      top_users = Usage.get_top_users_by_cost(today.year, today.month)

      assert length(top_users) == 2
      assert Enum.at(top_users, 0).user_id == user2.id
      assert Enum.at(top_users, 0).cost_cents == 100
      assert Enum.at(top_users, 1).user_id == user1.id
      assert Enum.at(top_users, 1).cost_cents == 20
    end
  end

  describe "format_cents/1" do
    test "formats cents as dollars with two decimal places" do
      assert Usage.format_cents(0) == "0.00"
      assert Usage.format_cents(1) == "0.01"
      assert Usage.format_cents(99) == "0.99"
      assert Usage.format_cents(100) == "1.00"
      assert Usage.format_cents(12_345) == "123.45"
    end

    test "handles non-integer values" do
      assert Usage.format_cents(nil) == "0.00"
    end
  end

  describe "alert threshold checking" do
    test "check_all_thresholds/0 creates alerts when thresholds exceeded" do
      provider = fixture(:ai_provider)
      model = fixture(:ai_model, provider: provider)
      user = fixture(:user)

      today = Date.utc_today()

      # Create threshold for $50/day total
      threshold =
        fixture(:alert_threshold, threshold_cents: 5000, period: "daily", scope: "total")

      # Create usage that exceeds threshold
      fixture(:daily_aggregate, user: user, model: model, date: today, cost_cents: 6000)

      alerts = Usage.check_all_thresholds()

      assert length(alerts) == 1
      alert = hd(alerts)
      assert alert.threshold_id == threshold.id
      assert alert.amount_cents == 6000
    end

    test "check_all_thresholds/0 does not create duplicate alerts" do
      provider = fixture(:ai_provider)
      model = fixture(:ai_model, provider: provider)
      user = fixture(:user)

      today = Date.utc_today()

      _threshold =
        fixture(:alert_threshold, threshold_cents: 5000, period: "daily", scope: "total")

      fixture(:daily_aggregate, user: user, model: model, date: today, cost_cents: 6000)

      # First check creates alert
      alerts1 = Usage.check_all_thresholds()
      assert length(alerts1) == 1

      # Second check should not create duplicate
      alerts2 = Usage.check_all_thresholds()
      assert alerts2 == []
    end
  end

  describe "alert management" do
    test "acknowledge_alert/2 marks alert as acknowledged" do
      threshold = fixture(:alert_threshold)
      alert = fixture(:alert, threshold: threshold)
      user = fixture(:user)

      assert alert.acknowledged_at == nil
      assert alert.acknowledged_by_id == nil

      {:ok, updated_alert} = Usage.acknowledge_alert(alert, user.id)

      assert updated_alert.acknowledged_at != nil
      assert updated_alert.acknowledged_by_id == user.id
    end

    test "count_unacknowledged_alerts/0 returns correct count" do
      threshold = fixture(:alert_threshold)

      # Create 2 unacknowledged alerts
      fixture(:alert, threshold: threshold)
      fixture(:alert, threshold: threshold)

      # Create 1 acknowledged alert
      user = fixture(:user)
      acknowledged = fixture(:alert, threshold: threshold)
      Usage.acknowledge_alert(acknowledged, user.id)

      count = Usage.count_unacknowledged_alerts()
      assert count == 2
    end

    test "list_alerts/1 filters by acknowledged status" do
      threshold = fixture(:alert_threshold)

      # Create unacknowledged alert
      unack_alert = fixture(:alert, threshold: threshold)

      # Create acknowledged alert
      user = fixture(:user)
      ack_alert = fixture(:alert, threshold: threshold)
      {:ok, ack_alert} = Usage.acknowledge_alert(ack_alert, user.id)

      unack_list = Usage.list_alerts(acknowledged: false)
      assert length(unack_list) == 1
      assert hd(unack_list).id == unack_alert.id

      ack_list = Usage.list_alerts(acknowledged: true)
      assert length(ack_list) == 1
      assert hd(ack_list).id == ack_alert.id

      all_list = Usage.list_alerts()
      assert length(all_list) == 2
    end
  end
end
