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
    date = DateTime.to_date(usage.inserted_at)

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

    DailyAggregate
    |> where([d], d.date >= ^start_date and d.date <= ^end_date)
    |> select([d], %{
      cost_cents: sum(d.cost_cents),
      request_count: sum(d.request_count),
      total_tokens: sum(d.total_tokens),
      input_tokens: sum(d.input_tokens),
      output_tokens: sum(d.output_tokens)
    })
    |> Repo.one() ||
      %{cost_cents: 0, request_count: 0, total_tokens: 0, input_tokens: 0, output_tokens: 0}
  end

  @doc """
  Gets top users by cost for a given month.
  """
  def get_top_users_by_cost(year, month, limit \\ 10) do
    {start_date, end_date} = month_date_range(year, month)

    DailyAggregate
    |> where([d], d.date >= ^start_date and d.date <= ^end_date)
    |> where([d], not is_nil(d.user_id))
    |> group_by([d], d.user_id)
    |> select([d], %{
      user_id: d.user_id,
      cost_cents: sum(d.cost_cents),
      request_count: sum(d.request_count),
      total_tokens: sum(d.total_tokens)
    })
    |> order_by([d], desc: sum(d.cost_cents))
    |> limit(^limit)
    |> Repo.all()
  end

  @doc """
  Gets daily cost breakdown for a month.
  """
  def get_daily_costs(year, month) do
    {start_date, end_date} = month_date_range(year, month)

    DailyAggregate
    |> where([d], d.date >= ^start_date and d.date <= ^end_date)
    |> group_by([d], d.date)
    |> select([d], %{
      date: d.date,
      cost_cents: sum(d.cost_cents),
      request_count: sum(d.request_count)
    })
    |> order_by([d], asc: d.date)
    |> Repo.all()
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
end
