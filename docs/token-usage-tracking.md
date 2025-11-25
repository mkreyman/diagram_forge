# Token Usage Tracking & Cost Management

## Overview

Track OpenAI API token usage and costs to understand spending patterns, per-user costs, and enable future paid membership decisions.

## Goals

1. **Track token usage** per request (input/output tokens separately)
2. **Aggregate by user** - daily and monthly rollups
3. **Calculate costs** based on configurable model pricing
4. **Admin visibility** - dashboard widgets, per-user breakdown, trends
5. **Alerts** - email and dashboard alerts when thresholds exceeded

## Current State

- Default model: `gpt-4o-mini` (configured in `config/runtime.exs`)
- AI client: `DiagramForge.AI.Client` - currently discards usage data from responses
- Three prompt types: diagram generation, syntax fixing (from configurable prompts)

---

## Database Schema

### AI Providers

```elixir
# priv/repo/migrations/xxx_create_ai_providers.exs
create table(:ai_providers, primary_key: false) do
  add :id, :binary_id, primary_key: true
  add :name, :string, null: false        # "OpenAI", "Anthropic"
  add :slug, :string, null: false        # "openai", "anthropic"
  add :api_base_url, :string             # "https://api.openai.com/v1"
  add :is_active, :boolean, default: true

  timestamps()
end

create unique_index(:ai_providers, [:slug])
```

### AI Models

```elixir
# priv/repo/migrations/xxx_create_ai_models.exs
create table(:ai_models, primary_key: false) do
  add :id, :binary_id, primary_key: true
  add :provider_id, references(:ai_providers, type: :binary_id, on_delete: :restrict), null: false
  add :name, :string, null: false           # "GPT-4o Mini"
  add :api_name, :string, null: false       # "gpt-4o-mini" (what we send to API)
  add :is_active, :boolean, default: true
  add :is_default, :boolean, default: false # Only one should be default
  add :capabilities, {:array, :string}      # ["chat", "json_mode"]

  timestamps()
end

create unique_index(:ai_models, [:provider_id, :api_name])
create index(:ai_models, [:is_default], where: "is_default = true")
```

### AI Model Prices

Track price history - prices change over time.

```elixir
# priv/repo/migrations/xxx_create_ai_model_prices.exs
create table(:ai_model_prices, primary_key: false) do
  add :id, :binary_id, primary_key: true
  add :model_id, references(:ai_models, type: :binary_id, on_delete: :cascade), null: false
  add :input_price_per_million, :decimal, precision: 12, scale: 6, null: false   # $ per 1M tokens
  add :output_price_per_million, :decimal, precision: 12, scale: 6, null: false  # $ per 1M tokens
  add :effective_from, :utc_datetime, null: false
  add :effective_until, :utc_datetime  # NULL = currently active

  timestamps()
end

create index(:ai_model_prices, [:model_id, :effective_from])
```

### Token Usage (Per-Request Log)

```elixir
# priv/repo/migrations/xxx_create_token_usage.exs
create table(:token_usage, primary_key: false) do
  add :id, :binary_id, primary_key: true
  add :user_id, references(:users, type: :binary_id, on_delete: :nilify_all)
  add :model_id, references(:ai_models, type: :binary_id, on_delete: :restrict), null: false
  add :operation, :string, null: false       # "diagram_generation", "syntax_fix"
  add :input_tokens, :integer, null: false
  add :output_tokens, :integer, null: false
  add :total_tokens, :integer, null: false
  add :cost_cents, :integer                  # Calculated cost in cents (for quick queries)
  add :metadata, :map, default: %{}          # Optional: diagram_id, prompt_key, etc.

  timestamps(updated_at: false)              # Log table, no updates
end

create index(:token_usage, [:user_id, :inserted_at])
create index(:token_usage, [:inserted_at])
create index(:token_usage, [:model_id])
```

### Usage Daily Aggregates

Materialized daily stats for efficient dashboard queries.

```elixir
# priv/repo/migrations/xxx_create_usage_daily_aggregates.exs
create table(:usage_daily_aggregates, primary_key: false) do
  add :id, :binary_id, primary_key: true
  add :user_id, references(:users, type: :binary_id, on_delete: :cascade)
  add :date, :date, null: false
  add :model_id, references(:ai_models, type: :binary_id, on_delete: :restrict), null: false
  add :request_count, :integer, default: 0
  add :input_tokens, :integer, default: 0
  add :output_tokens, :integer, default: 0
  add :total_tokens, :integer, default: 0
  add :cost_cents, :integer, default: 0

  timestamps()
end

create unique_index(:usage_daily_aggregates, [:user_id, :date, :model_id])
create index(:usage_daily_aggregates, [:date])
create index(:usage_daily_aggregates, [:user_id, :date])
```

### Alert Thresholds

```elixir
# priv/repo/migrations/xxx_create_usage_alert_thresholds.exs
create table(:usage_alert_thresholds, primary_key: false) do
  add :id, :binary_id, primary_key: true
  add :name, :string, null: false                    # "per_user_monthly", "total_monthly"
  add :threshold_cents, :integer, null: false        # Amount in cents
  add :period, :string, null: false                  # "daily", "monthly"
  add :scope, :string, null: false                   # "per_user", "total"
  add :is_active, :boolean, default: true
  add :notify_email, :boolean, default: true
  add :notify_dashboard, :boolean, default: true

  timestamps()
end

create unique_index(:usage_alert_thresholds, [:name])
```

### Alert History

```elixir
# priv/repo/migrations/xxx_create_usage_alerts.exs
create table(:usage_alerts, primary_key: false) do
  add :id, :binary_id, primary_key: true
  add :threshold_id, references(:usage_alert_thresholds, type: :binary_id, on_delete: :cascade), null: false
  add :user_id, references(:users, type: :binary_id, on_delete: :cascade)  # NULL for total alerts
  add :period_start, :date, null: false
  add :period_end, :date, null: false
  add :amount_cents, :integer, null: false
  add :email_sent_at, :utc_datetime
  add :acknowledged_at, :utc_datetime
  add :acknowledged_by_id, references(:users, type: :binary_id, on_delete: :nilify_all)

  timestamps(updated_at: false)
end

create index(:usage_alerts, [:threshold_id, :period_start])
create index(:usage_alerts, [:user_id, :period_start])
create index(:usage_alerts, [:acknowledged_at], where: "acknowledged_at IS NULL")
```

---

## Current Pricing Reference

As of November 2024 (store in database, not hardcoded):

| Model | Input (per 1M) | Output (per 1M) |
|-------|----------------|-----------------|
| gpt-4o-mini | $0.15 | $0.60 |
| gpt-4o | $2.50 | $10.00 |
| gpt-4-turbo | $10.00 | $30.00 |

---

## Implementation

### 1. Modify AI Client to Return Usage

Update `DiagramForge.AI.Client` to return token usage:

```elixir
# Current: returns just content string
def chat!(messages, opts \\ [])

# New: returns {content, usage} tuple
def chat!(messages, opts \\ []) do
  # ... existing code ...
  case result do
    {:ok, content, usage} ->
      # Record usage asynchronously (don't block the request)
      if opts[:track_usage] != false do
        Task.start(fn ->
          record_usage(opts[:user_id], opts[:operation], usage, model)
        end)
      end
      content
    # ...
  end
end

# Also expose a version that returns usage for callers who need it
def chat_with_usage!(messages, opts \\ []) do
  # Returns {content, %{input_tokens: x, output_tokens: y, total_tokens: z}}
end
```

### 2. Context Module

```elixir
defmodule DiagramForge.Usage do
  @moduledoc """
  Token usage tracking and cost calculation.
  """

  alias DiagramForge.Repo
  alias DiagramForge.Usage.{TokenUsage, DailyAggregate, AIModel, AIModelPrice}

  @doc """
  Records token usage for a request.
  """
  def record_usage(attrs) do
    %TokenUsage{}
    |> TokenUsage.changeset(attrs)
    |> Repo.insert()
    |> tap(fn
      {:ok, usage} -> update_daily_aggregate(usage)
      _ -> :ok
    end)
  end

  @doc """
  Gets the current price for a model.
  """
  def get_current_price(model_id) do
    AIModelPrice
    |> where([p], p.model_id == ^model_id)
    |> where([p], p.effective_from <= ^DateTime.utc_now())
    |> where([p], is_nil(p.effective_until) or p.effective_until > ^DateTime.utc_now())
    |> order_by([p], desc: p.effective_from)
    |> limit(1)
    |> Repo.one()
  end

  @doc """
  Calculates cost in cents for given token counts.
  """
  def calculate_cost(input_tokens, output_tokens, %AIModelPrice{} = price) do
    input_cost = Decimal.mult(price.input_price_per_million, input_tokens)
                 |> Decimal.div(1_000_000)
    output_cost = Decimal.mult(price.output_price_per_million, output_tokens)
                  |> Decimal.div(1_000_000)

    Decimal.add(input_cost, output_cost)
    |> Decimal.mult(100)  # Convert to cents
    |> Decimal.round(0)
    |> Decimal.to_integer()
  end

  @doc """
  Gets monthly usage for a user.
  """
  def get_user_monthly_usage(user_id, year, month) do
    start_date = Date.new!(year, month, 1)
    end_date = Date.end_of_month(start_date)

    DailyAggregate
    |> where([d], d.user_id == ^user_id)
    |> where([d], d.date >= ^start_date and d.date <= ^end_date)
    |> Repo.aggregate(:sum, :cost_cents) || 0
  end

  @doc """
  Gets total monthly usage across all users.
  """
  def get_total_monthly_usage(year, month) do
    start_date = Date.new!(year, month, 1)
    end_date = Date.end_of_month(start_date)

    DailyAggregate
    |> where([d], d.date >= ^start_date and d.date <= ^end_date)
    |> Repo.aggregate(:sum, :cost_cents) || 0
  end
end
```

### 3. Daily Aggregation (Oban Job)

```elixir
defmodule DiagramForge.Workers.AggregateUsageWorker do
  @moduledoc """
  Aggregates token usage into daily rollups.
  Runs nightly via Oban cron.
  """
  use Oban.Worker, queue: :default

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"date" => date_string}}) do
    date = Date.from_iso8601!(date_string)
    DiagramForge.Usage.aggregate_day(date)
  end
end

# In config/config.exs, add to Oban crontab:
# {"0 1 * * *", DiagramForge.Workers.AggregateUsageWorker, args: %{date: "yesterday"}}
```

### 4. Alert Checking (Oban Job)

```elixir
defmodule DiagramForge.Workers.CheckUsageAlertsWorker do
  @moduledoc """
  Checks usage against thresholds and sends alerts.
  Runs hourly via Oban cron.
  """
  use Oban.Worker, queue: :default

  @impl Oban.Worker
  def perform(_job) do
    DiagramForge.Usage.Alerts.check_all_thresholds()
  end
end
```

---

## Admin UI

### 1. Dashboard Widget

Add to existing admin dashboard (`lib/diagram_forge_web/live/admin/dashboard_live.ex`):

```heex
<%!-- Usage Stats Card --%>
<div class="bg-base-100 rounded-lg border border-base-300 p-6 shadow-sm">
  <h2 class="text-lg font-semibold text-base-content mb-4">API Usage This Month</h2>
  <dl class="space-y-3">
    <div class="flex justify-between">
      <dt class="text-sm text-base-content/70">Total Cost</dt>
      <dd class="text-sm font-medium">${format_cents(@monthly_cost)}</dd>
    </div>
    <div class="flex justify-between">
      <dt class="text-sm text-base-content/70">Total Requests</dt>
      <dd class="text-sm font-medium">{@monthly_requests}</dd>
    </div>
    <div class="flex justify-between">
      <dt class="text-sm text-base-content/70">Total Tokens</dt>
      <dd class="text-sm font-medium">{Number.Delimit.number_to_delimited(@monthly_tokens)}</dd>
    </div>
  </dl>
  <.link navigate={~p"/admin/usage"} class="btn btn-sm btn-ghost mt-4">
    View Details →
  </.link>
</div>

<%!-- Active Alerts Banner --%>
<%= if @unacknowledged_alerts > 0 do %>
  <div class="alert alert-warning">
    <Backpex.HTML.CoreComponents.icon name="hero-exclamation-triangle" class="size-5" />
    <span>{@unacknowledged_alerts} usage alert(s) require attention</span>
    <.link navigate={~p"/admin/usage/alerts"} class="btn btn-sm">View</.link>
  </div>
<% end %>
```

### 2. New Admin Pages

| Route | Page | Purpose |
|-------|------|---------|
| `/admin/usage` | Usage Dashboard | Monthly overview, charts, per-user breakdown |
| `/admin/usage/alerts` | Alert History | View/acknowledge alerts |
| `/admin/ai-providers` | AI Providers | Backpex CRUD |
| `/admin/ai-models` | AI Models | Backpex CRUD |
| `/admin/ai-model-prices` | Model Pricing | Backpex CRUD with effective dates |
| `/admin/usage-thresholds` | Alert Thresholds | Configure alert limits |

### 3. Usage Dashboard Wireframe

```
┌─────────────────────────────────────────────────────────────────┐
│ API Usage - November 2024                            [< Prev] [Next >] │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐          │
│  │ Total Cost   │  │ Requests     │  │ Tokens       │          │
│  │ $12.47       │  │ 1,234        │  │ 2.1M         │          │
│  │ ↑ 15% vs Oct │  │ ↑ 8% vs Oct  │  │ ↑ 12% vs Oct │          │
│  └──────────────┘  └──────────────┘  └──────────────┘          │
│                                                                 │
│  Daily Cost Trend                                               │
│  ┌─────────────────────────────────────────────────────────┐   │
│  │     $2 ─┼────────────────────────────────────────────   │   │
│  │         │    ╭─╮                           ╭─╮          │   │
│  │     $1 ─┼───╯   ╰──╮     ╭──╮     ╭──╮───╯   ╰───      │   │
│  │         │          ╰─────╯  ╰─────╯  ╰               │   │
│  │      $0 ─┼────────────────────────────────────────────   │   │
│  │          1    5    10   15   20   25   30              │   │
│  └─────────────────────────────────────────────────────────┘   │
│                                                                 │
│  Top Users by Cost                                              │
│  ┌────────────────────────────────────────────────────────┐    │
│  │ User                    │ Requests │ Tokens  │ Cost    │    │
│  ├────────────────────────────────────────────────────────┤    │
│  │ user@example.com        │ 245      │ 450K    │ $3.21   │    │
│  │ another@example.com     │ 189      │ 380K    │ $2.85   │    │
│  │ third@example.com       │ 156      │ 290K    │ $2.10   │    │
│  └────────────────────────────────────────────────────────┘    │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

---

## Alert Configuration

### Default Thresholds

| Name | Scope | Period | Threshold | Actions |
|------|-------|--------|-----------|---------|
| `per_user_monthly` | per_user | monthly | $10.00 | Email + Dashboard |
| `total_monthly` | total | monthly | $50.00 | Email + Dashboard |

### Email Notification

```elixir
defmodule DiagramForge.Usage.AlertMailer do
  use DiagramForge, :mailer

  def usage_threshold_exceeded(admin_email, alert) do
    new()
    |> to(admin_email)
    |> from({"DiagramForge", "noreply@diagramforge.com"})
    |> subject("[DiagramForge] Usage Alert: #{alert.threshold.name}")
    |> render_body(:usage_alert, alert: alert)
  end
end
```

---

## Seed Data

```elixir
# priv/repo/seeds/ai_config_seeds.exs

alias DiagramForge.Repo
alias DiagramForge.Usage.{AIProvider, AIModel, AIModelPrice, UsageAlertThreshold}

# OpenAI Provider
{:ok, openai} = Repo.insert(%AIProvider{
  name: "OpenAI",
  slug: "openai",
  api_base_url: "https://api.openai.com/v1",
  is_active: true
})

# GPT-4o-mini (default)
{:ok, gpt4o_mini} = Repo.insert(%AIModel{
  provider_id: openai.id,
  name: "GPT-4o Mini",
  api_name: "gpt-4o-mini",
  is_active: true,
  is_default: true,
  capabilities: ["chat", "json_mode"]
})

# GPT-4o-mini pricing
Repo.insert!(%AIModelPrice{
  model_id: gpt4o_mini.id,
  input_price_per_million: Decimal.new("0.15"),
  output_price_per_million: Decimal.new("0.60"),
  effective_from: ~U[2024-07-01 00:00:00Z]
})

# Default alert thresholds
Repo.insert!(%UsageAlertThreshold{
  name: "per_user_monthly",
  threshold_cents: 1000,  # $10.00
  period: "monthly",
  scope: "per_user",
  is_active: true,
  notify_email: true,
  notify_dashboard: true
})

Repo.insert!(%UsageAlertThreshold{
  name: "total_monthly",
  threshold_cents: 5000,  # $50.00
  period: "monthly",
  scope: "total",
  is_active: true,
  notify_email: true,
  notify_dashboard: true
})
```

---

## Implementation Checklist

### Phase 1: Schema & Core Logic
- [ ] Create migrations for all tables
- [ ] Create Ecto schemas (AIProvider, AIModel, AIModelPrice, TokenUsage, DailyAggregate, UsageAlertThreshold, UsageAlert)
- [ ] Create `DiagramForge.Usage` context module
- [ ] Modify `DiagramForge.AI.Client` to capture and return token usage
- [ ] Update diagram generation calls to pass user_id and operation
- [ ] Create seed data for OpenAI + gpt-4o-mini + current pricing

### Phase 2: Aggregation & Alerts
- [ ] Create Oban worker for daily aggregation
- [ ] Create Oban worker for alert checking
- [ ] Configure Oban crontab for workers
- [ ] Create alert mailer and email template
- [ ] Test alert triggering

### Phase 3: Admin UI
- [ ] Add Backpex resources for AIProvider, AIModel, AIModelPrice
- [ ] Add Backpex resources for UsageAlertThreshold
- [ ] Create Usage Dashboard LiveView with charts
- [ ] Create Alert History page
- [ ] Add dashboard widget to existing admin dashboard
- [ ] Add navigation links for new pages

### Phase 4: Polish
- [ ] Add usage export (CSV)
- [ ] Add date range filtering
- [ ] Add model breakdown in usage dashboard
- [ ] Write tests for cost calculation and aggregation
- [ ] Documentation

---

## Future Considerations

- **Multiple AI providers**: Schema supports Anthropic, Google, etc.
- **Usage quotas**: Per-user limits (not just alerts)
- **Billing integration**: If implementing paid memberships
- **Real-time dashboard**: PubSub updates for live cost tracking
