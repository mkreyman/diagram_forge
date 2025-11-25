defmodule DiagramForge.Usage do
  @moduledoc """
  Context for token usage tracking and cost calculation.
  """

  import Ecto.Query

  alias DiagramForge.Repo
  alias DiagramForge.Usage.{AIModel, AIModelPrice, AIProvider, DailyAggregate, TokenUsage}

  # ============================================================================
  # AI Providers
  # ============================================================================

  @doc """
  Lists all AI providers.
  """
  def list_providers do
    Repo.all(AIProvider)
  end

  @doc """
  Gets a provider by slug.
  """
  def get_provider_by_slug(slug) do
    Repo.get_by(AIProvider, slug: slug)
  end

  # ============================================================================
  # AI Models
  # ============================================================================

  @doc """
  Lists all AI models, optionally filtered by provider.
  """
  def list_models(opts \\ []) do
    AIModel
    |> maybe_filter_by_provider(opts[:provider_id])
    |> maybe_filter_active(opts[:active_only])
    |> Repo.all()
    |> Repo.preload(:provider)
  end

  defp maybe_filter_by_provider(query, nil), do: query

  defp maybe_filter_by_provider(query, provider_id),
    do: where(query, [m], m.provider_id == ^provider_id)

  defp maybe_filter_active(query, true), do: where(query, [m], m.is_active == true)
  defp maybe_filter_active(query, _), do: query

  @doc """
  Gets the default AI model.
  """
  def get_default_model do
    AIModel
    |> where([m], m.is_default == true and m.is_active == true)
    |> limit(1)
    |> Repo.one()
    |> Repo.preload(:provider)
  end

  @doc """
  Gets an AI model by its API name (e.g., "gpt-4o-mini").
  """
  def get_model_by_api_name(api_name) do
    AIModel
    |> where([m], m.api_name == ^api_name)
    |> Repo.one()
    |> Repo.preload(:provider)
  end

  # ============================================================================
  # Pricing
  # ============================================================================

  @doc """
  Gets the current price for a model.
  Returns the price record that is effective now (effective_from <= now, and effective_until is nil or > now).
  """
  def get_current_price(model_id) do
    now = DateTime.utc_now()

    AIModelPrice
    |> where([p], p.model_id == ^model_id)
    |> where([p], p.effective_from <= ^now)
    |> where([p], is_nil(p.effective_until) or p.effective_until > ^now)
    |> order_by([p], desc: p.effective_from)
    |> limit(1)
    |> Repo.one()
  end

  @doc """
  Calculates cost in cents for given token counts.
  """
  def calculate_cost(input_tokens, output_tokens, %AIModelPrice{} = price) do
    input_cost =
      Decimal.mult(price.input_price_per_million, input_tokens)
      |> Decimal.div(1_000_000)

    output_cost =
      Decimal.mult(price.output_price_per_million, output_tokens)
      |> Decimal.div(1_000_000)

    Decimal.add(input_cost, output_cost)
    |> Decimal.mult(100)
    |> Decimal.round(0)
    |> Decimal.to_integer()
  end

  def calculate_cost(_input_tokens, _output_tokens, nil), do: nil

  @doc """
  Calculates cost in cents for given token counts using the model's current price.
  Returns 0 if no pricing is available.
  """
  def calculate_cost_for_tokens(model_id, input_tokens, output_tokens)
      when is_binary(model_id) do
    case get_current_price(model_id) do
      nil -> 0
      price -> calculate_cost(input_tokens || 0, output_tokens || 0, price)
    end
  end

  def calculate_cost_for_tokens(_, _, _), do: 0

  # ============================================================================
  # Token Usage Recording
  # ============================================================================

  @doc """
  Records token usage for a request.
  Automatically calculates cost if pricing is available.
  """
  def record_usage(attrs) do
    model_id = attrs[:model_id]
    price = if model_id, do: get_current_price(model_id), else: nil

    cost_cents =
      if price do
        calculate_cost(attrs[:input_tokens] || 0, attrs[:output_tokens] || 0, price)
      else
        nil
      end

    attrs = Map.put(attrs, :cost_cents, cost_cents)

    %TokenUsage{}
    |> TokenUsage.changeset(attrs)
    |> Repo.insert()
    |> tap(fn
      {:ok, usage} -> update_daily_aggregate(usage)
      _ -> :ok
    end)
  end

  @doc """
  Records usage asynchronously (fire and forget).
  Use this in the AI client to avoid blocking the request.
  """
  def record_usage_async(attrs) do
    Task.start(fn -> record_usage(attrs) end)
  end

  # ============================================================================
  # Daily Aggregates
  # ============================================================================

  defp update_daily_aggregate(%TokenUsage{} = usage) do
    date = NaiveDateTime.to_date(usage.inserted_at)

    # Use upsert to atomically increment counters
    Repo.insert(
      %DailyAggregate{
        user_id: usage.user_id,
        model_id: usage.model_id,
        date: date,
        request_count: 1,
        input_tokens: usage.input_tokens,
        output_tokens: usage.output_tokens,
        total_tokens: usage.total_tokens,
        cost_cents: usage.cost_cents || 0
      },
      on_conflict: [
        inc: [
          request_count: 1,
          input_tokens: usage.input_tokens,
          output_tokens: usage.output_tokens,
          total_tokens: usage.total_tokens,
          cost_cents: usage.cost_cents || 0
        ]
      ],
      conflict_target: [:user_id, :date, :model_id]
    )
  end

  # ============================================================================
  # Usage Queries
  # ============================================================================

  @doc """
  Gets monthly usage for a specific user.
  Returns total cost in cents.
  """
  def get_user_monthly_usage(user_id, year, month) do
    {start_date, end_date} = month_date_range(year, month)

    DailyAggregate
    |> where([d], d.user_id == ^user_id)
    |> where([d], d.date >= ^start_date and d.date <= ^end_date)
    |> Repo.aggregate(:sum, :cost_cents) || 0
  end

  @doc """
  Gets total monthly usage across all users.
  Returns total cost in cents.
  """
  def get_total_monthly_usage(year, month) do
    {start_date, end_date} = month_date_range(year, month)

    DailyAggregate
    |> where([d], d.date >= ^start_date and d.date <= ^end_date)
    |> Repo.aggregate(:sum, :cost_cents) || 0
  end

  @doc """
  Gets monthly usage summary with request count and token totals.
  """
  def get_monthly_summary(year, month) do
    {start_date, end_date} = month_date_range(year, month)
    get_summary_for_range(start_date, end_date)
  end

  @doc """
  Gets usage summary for a custom date range.
  Calculates cost from aggregated tokens using current pricing (via model breakdown).
  """
  def get_summary_for_range(start_date, end_date) do
    # Get model breakdown which calculates costs from tokens
    model_breakdown = get_usage_by_model_for_range(start_date, end_date)

    # Sum up the calculated costs and token counts
    Enum.reduce(model_breakdown, initial_summary(), fn row, acc ->
      %{
        cost_cents: acc.cost_cents + (row.cost_cents || 0),
        request_count: acc.request_count + (row.request_count || 0),
        total_tokens: acc.total_tokens + (row.total_tokens || 0),
        input_tokens: acc.input_tokens + (row.input_tokens || 0),
        output_tokens: acc.output_tokens + (row.output_tokens || 0)
      }
    end)
  end

  defp initial_summary do
    %{cost_cents: 0, request_count: 0, total_tokens: 0, input_tokens: 0, output_tokens: 0}
  end

  @doc """
  Gets top users by cost for a given month.
  """
  def get_top_users_by_cost(year, month, limit \\ 10) do
    {start_date, end_date} = month_date_range(year, month)
    get_top_users_for_range(start_date, end_date, limit)
  end

  @doc """
  Gets top users by cost for a custom date range.
  Calculates cost from aggregated tokens using current pricing.
  """
  def get_top_users_for_range(start_date, end_date, limit \\ 10) do
    # Get per-user, per-model data so we can calculate costs accurately
    DailyAggregate
    |> where([d], d.date >= ^start_date and d.date <= ^end_date)
    |> where([d], not is_nil(d.user_id))
    |> group_by([d], [d.user_id, d.model_id])
    |> select([d], %{
      user_id: d.user_id,
      model_id: d.model_id,
      input_tokens: sum(d.input_tokens),
      output_tokens: sum(d.output_tokens),
      request_count: sum(d.request_count),
      total_tokens: sum(d.total_tokens)
    })
    |> Repo.all()
    # Calculate cost for each user's model usage
    |> Enum.map(fn row ->
      cost_cents = calculate_cost_for_tokens(row.model_id, row.input_tokens, row.output_tokens)
      Map.put(row, :cost_cents, cost_cents)
    end)
    # Aggregate by user
    |> Enum.group_by(& &1.user_id)
    |> Enum.map(fn {user_id, rows} ->
      %{
        user_id: user_id,
        cost_cents: Enum.sum(Enum.map(rows, & &1.cost_cents)),
        request_count: Enum.sum(Enum.map(rows, & &1.request_count)),
        total_tokens: Enum.sum(Enum.map(rows, & &1.total_tokens))
      }
    end)
    |> Enum.sort_by(& &1.cost_cents, :desc)
    |> Enum.take(limit)
  end

  @doc """
  Gets daily cost breakdown for a month.
  """
  def get_daily_costs(year, month) do
    {start_date, end_date} = month_date_range(year, month)
    get_daily_costs_for_range(start_date, end_date)
  end

  @doc """
  Gets daily cost breakdown for a custom date range.
  Calculates cost from aggregated tokens using current pricing.
  """
  def get_daily_costs_for_range(start_date, end_date) do
    # Get per-day, per-model data so we can calculate costs accurately
    DailyAggregate
    |> where([d], d.date >= ^start_date and d.date <= ^end_date)
    |> group_by([d], [d.date, d.model_id])
    |> select([d], %{
      date: d.date,
      model_id: d.model_id,
      input_tokens: sum(d.input_tokens),
      output_tokens: sum(d.output_tokens),
      request_count: sum(d.request_count)
    })
    |> Repo.all()
    # Calculate cost for each model's daily usage
    |> Enum.map(fn row ->
      cost_cents = calculate_cost_for_tokens(row.model_id, row.input_tokens, row.output_tokens)
      Map.put(row, :cost_cents, cost_cents)
    end)
    # Aggregate by date
    |> Enum.group_by(& &1.date)
    |> Enum.map(fn {date, rows} ->
      %{
        date: date,
        cost_cents: Enum.sum(Enum.map(rows, & &1.cost_cents)),
        request_count: Enum.sum(Enum.map(rows, & &1.request_count))
      }
    end)
    |> Enum.sort_by(& &1.date, Date)
  end

  @doc """
  Gets usage breakdown by model for a given month.
  Returns list of maps with model info and usage stats.
  """
  def get_usage_by_model(year, month) do
    {start_date, end_date} = month_date_range(year, month)
    get_usage_by_model_for_range(start_date, end_date)
  end

  @doc """
  Gets usage breakdown by model for a custom date range.
  Calculates cost from aggregated tokens using current pricing.
  """
  def get_usage_by_model_for_range(start_date, end_date) do
    DailyAggregate
    |> where([d], d.date >= ^start_date and d.date <= ^end_date)
    |> where([d], not is_nil(d.model_id))
    |> join(:inner, [d], m in AIModel, on: d.model_id == m.id)
    |> group_by([d, m], [d.model_id, m.name, m.api_name])
    |> select([d, m], %{
      model_id: d.model_id,
      model_name: m.name,
      api_name: m.api_name,
      request_count: sum(d.request_count),
      input_tokens: sum(d.input_tokens),
      output_tokens: sum(d.output_tokens),
      total_tokens: sum(d.total_tokens)
    })
    |> Repo.all()
    |> Enum.map(fn row ->
      cost_cents = calculate_cost_for_tokens(row.model_id, row.input_tokens, row.output_tokens)
      Map.put(row, :cost_cents, cost_cents)
    end)
    |> Enum.sort_by(& &1.cost_cents, :desc)
  end

  # ============================================================================
  # CSV Export
  # ============================================================================

  @doc """
  Exports usage data as CSV for a given month.
  Returns a CSV string with headers.
  """
  def export_usage_csv(year, month) do
    {start_date, end_date} = month_date_range(year, month)
    export_usage_csv_for_range(start_date, end_date)
  end

  @doc """
  Exports usage data as CSV for a custom date range.
  Returns a CSV string with headers.
  """
  def export_usage_csv_for_range(start_date, end_date) do
    rows =
      TokenUsage
      |> where([t], fragment("DATE(?)", t.inserted_at) >= ^start_date)
      |> where([t], fragment("DATE(?)", t.inserted_at) <= ^end_date)
      |> join(:left, [t], m in AIModel, on: t.model_id == m.id)
      |> join(:left, [t, m], u in DiagramForge.Accounts.User, on: t.user_id == u.id)
      |> select([t, m, u], %{
        timestamp: t.inserted_at,
        user_email: u.email,
        model: m.api_name,
        operation: t.operation,
        input_tokens: t.input_tokens,
        output_tokens: t.output_tokens,
        total_tokens: t.total_tokens,
        cost_cents: t.cost_cents
      })
      |> order_by([t], asc: t.inserted_at)
      |> Repo.all()

    headers = [
      "Timestamp",
      "User Email",
      "Model",
      "Operation",
      "Input Tokens",
      "Output Tokens",
      "Total Tokens",
      "Cost ($)"
    ]

    csv_rows =
      Enum.map(rows, fn row ->
        [
          format_datetime(row.timestamp),
          row.user_email || "anonymous",
          row.model || "unknown",
          row.operation || "unknown",
          to_string(row.input_tokens || 0),
          to_string(row.output_tokens || 0),
          to_string(row.total_tokens || 0),
          format_cents(row.cost_cents || 0)
        ]
      end)

    [headers | csv_rows]
    |> Enum.map_join("\n", &Enum.join(&1, ","))
  end

  defp format_datetime(nil), do: ""

  defp format_datetime(datetime) do
    Calendar.strftime(datetime, "%Y-%m-%d %H:%M:%S")
  end

  # ============================================================================
  # Helpers
  # ============================================================================

  defp month_date_range(year, month) do
    start_date = Date.new!(year, month, 1)
    end_date = Date.end_of_month(start_date)
    {start_date, end_date}
  end

  @doc """
  Formats cents as dollars string.
  """
  def format_cents(cents) when is_integer(cents) do
    dollars = cents / 100
    :erlang.float_to_binary(dollars, decimals: 2)
  end

  def format_cents(_), do: "0.00"

  # ============================================================================
  # Alert Thresholds
  # ============================================================================

  alias DiagramForge.Usage.{Alert, AlertThreshold}

  @doc """
  Lists all active alert thresholds.
  """
  def list_active_thresholds do
    AlertThreshold
    |> where([t], t.is_active == true)
    |> Repo.all()
  end

  @doc """
  Gets a threshold by name.
  """
  def get_threshold_by_name(name) do
    Repo.get_by(AlertThreshold, name: name)
  end

  @doc """
  Creates a new alert threshold.
  """
  def create_threshold(attrs) do
    %AlertThreshold{}
    |> AlertThreshold.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates an alert threshold.
  """
  def update_threshold(%AlertThreshold{} = threshold, attrs) do
    threshold
    |> AlertThreshold.changeset(attrs)
    |> Repo.update()
  end

  # ============================================================================
  # Alert Checking & Creation
  # ============================================================================

  @doc """
  Checks all active thresholds and creates alerts for any that are exceeded.
  Returns a list of newly created alerts.
  """
  def check_all_thresholds do
    thresholds = list_active_thresholds()

    Enum.flat_map(thresholds, fn threshold ->
      case check_threshold(threshold) do
        {:ok, alerts} -> alerts
        {:error, _} -> []
      end
    end)
  end

  @doc """
  Checks a single threshold and creates alerts if exceeded.
  """
  def check_threshold(%AlertThreshold{} = threshold) do
    {start_date, end_date} = threshold_period_range(threshold)

    case threshold.scope do
      "total" ->
        check_total_threshold(threshold, start_date, end_date)

      "per_user" ->
        check_per_user_threshold(threshold, start_date, end_date)
    end
  end

  defp threshold_period_range(%AlertThreshold{period: "daily"}) do
    today = Date.utc_today()
    {today, today}
  end

  defp threshold_period_range(%AlertThreshold{period: "monthly"}) do
    today = Date.utc_today()
    start_date = Date.beginning_of_month(today)
    end_date = Date.end_of_month(today)
    {start_date, end_date}
  end

  defp check_total_threshold(threshold, start_date, end_date) do
    total_cost = get_total_cost_for_period(start_date, end_date)
    threshold_exceeded = total_cost >= threshold.threshold_cents
    alert_already_exists = alert_exists?(threshold.id, nil, start_date, end_date)

    if threshold_exceeded and not alert_already_exists do
      create_total_alert(threshold, start_date, end_date, total_cost)
    else
      {:ok, []}
    end
  end

  defp create_total_alert(threshold, start_date, end_date, total_cost) do
    case create_alert(%{
           threshold_id: threshold.id,
           user_id: nil,
           period_start: start_date,
           period_end: end_date,
           amount_cents: total_cost
         }) do
      {:ok, alert} -> {:ok, [alert]}
      error -> error
    end
  end

  defp check_per_user_threshold(threshold, start_date, end_date) do
    users_over_threshold =
      get_users_over_threshold(threshold.threshold_cents, start_date, end_date)

    alerts =
      Enum.reduce(users_over_threshold, [], fn %{user_id: user_id, cost_cents: cost}, acc ->
        maybe_create_user_alert(threshold, user_id, start_date, end_date, cost, acc)
      end)

    {:ok, alerts}
  end

  defp maybe_create_user_alert(threshold, user_id, start_date, end_date, cost, acc) do
    if alert_exists?(threshold.id, user_id, start_date, end_date) do
      acc
    else
      create_user_alert(threshold, user_id, start_date, end_date, cost, acc)
    end
  end

  defp create_user_alert(threshold, user_id, start_date, end_date, cost, acc) do
    case create_alert(%{
           threshold_id: threshold.id,
           user_id: user_id,
           period_start: start_date,
           period_end: end_date,
           amount_cents: cost
         }) do
      {:ok, alert} -> [alert | acc]
      _ -> acc
    end
  end

  defp get_total_cost_for_period(start_date, end_date) do
    DailyAggregate
    |> where([d], d.date >= ^start_date and d.date <= ^end_date)
    |> Repo.aggregate(:sum, :cost_cents) || 0
  end

  defp get_users_over_threshold(threshold_cents, start_date, end_date) do
    DailyAggregate
    |> where([d], d.date >= ^start_date and d.date <= ^end_date)
    |> where([d], not is_nil(d.user_id))
    |> group_by([d], d.user_id)
    |> having([d], sum(d.cost_cents) >= ^threshold_cents)
    |> select([d], %{user_id: d.user_id, cost_cents: sum(d.cost_cents)})
    |> Repo.all()
  end

  defp alert_exists?(threshold_id, user_id, period_start, period_end) do
    query =
      Alert
      |> where([a], a.threshold_id == ^threshold_id)
      |> where([a], a.period_start == ^period_start)
      |> where([a], a.period_end == ^period_end)

    query =
      if user_id do
        where(query, [a], a.user_id == ^user_id)
      else
        where(query, [a], is_nil(a.user_id))
      end

    Repo.exists?(query)
  end

  @doc """
  Creates a new usage alert.
  """
  def create_alert(attrs) do
    %Alert{}
    |> Alert.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Marks an alert as email sent.
  """
  def mark_alert_email_sent(%Alert{} = alert) do
    alert
    |> Ecto.Changeset.change(email_sent_at: DateTime.utc_now() |> DateTime.truncate(:second))
    |> Repo.update()
  end

  # ============================================================================
  # Alert Queries
  # ============================================================================

  @doc """
  Lists unacknowledged alerts.
  """
  def list_unacknowledged_alerts do
    Alert
    |> where([a], is_nil(a.acknowledged_at))
    |> order_by([a], desc: a.inserted_at)
    |> Repo.all()
    |> Repo.preload([:threshold, :user])
  end

  @doc """
  Counts unacknowledged alerts.
  """
  def count_unacknowledged_alerts do
    Alert
    |> where([a], is_nil(a.acknowledged_at))
    |> Repo.aggregate(:count)
  end

  @doc """
  Gets an alert by ID.
  """
  def get_alert(id) do
    Alert
    |> Repo.get(id)
    |> Repo.preload([:threshold, :user, :acknowledged_by])
  end

  @doc """
  Acknowledges an alert.
  """
  def acknowledge_alert(%Alert{} = alert, admin_user_id) do
    alert
    |> Alert.acknowledge_changeset(admin_user_id)
    |> Repo.update()
  end

  @doc """
  Lists all alerts with optional filters.
  """
  def list_alerts(opts \\ []) do
    Alert
    |> maybe_filter_acknowledged(opts[:acknowledged])
    |> order_by([a], desc: a.inserted_at)
    |> limit(^(opts[:limit] || 50))
    |> Repo.all()
    |> Repo.preload([:threshold, :user, :acknowledged_by])
  end

  defp maybe_filter_acknowledged(query, nil), do: query

  defp maybe_filter_acknowledged(query, true),
    do: where(query, [a], not is_nil(a.acknowledged_at))

  defp maybe_filter_acknowledged(query, false),
    do: where(query, [a], is_nil(a.acknowledged_at))

  @doc """
  Gets alerts that need email notifications sent.
  """
  def list_alerts_needing_email do
    Alert
    |> where([a], is_nil(a.email_sent_at))
    |> join(:inner, [a], t in AlertThreshold, on: a.threshold_id == t.id)
    |> where([a, t], t.notify_email == true)
    |> Repo.all()
    |> Repo.preload([:threshold, :user])
  end
end
