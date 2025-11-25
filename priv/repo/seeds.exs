# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs
#
# Inside the script, you can read and write to any of your
# repositories directly:
#
#     DiagramForge.Repo.insert!(%DiagramForge.SomeSchema{})
#
# We recommend using the bang functions (`insert!`, `update!`
# and so on) as they will fail if something goes wrong.

alias DiagramForge.Repo
alias DiagramForge.Usage.{AIProvider, AIModel, AIModelPrice, AlertThreshold}

# ============================================================================
# AI Providers and Models
# ============================================================================

# OpenAI Provider
openai =
  case Repo.get_by(AIProvider, slug: "openai") do
    nil ->
      Repo.insert!(%AIProvider{
        name: "OpenAI",
        slug: "openai",
        api_base_url: "https://api.openai.com/v1",
        is_active: true
      })

    existing ->
      existing
  end

IO.puts("✓ OpenAI provider: #{openai.id}")

# GPT-4o-mini (default model)
gpt4o_mini =
  case Repo.get_by(AIModel, api_name: "gpt-4o-mini") do
    nil ->
      Repo.insert!(%AIModel{
        provider_id: openai.id,
        name: "GPT-4o Mini",
        api_name: "gpt-4o-mini",
        is_active: true,
        is_default: true,
        capabilities: ["chat", "json_mode"]
      })

    existing ->
      existing
  end

IO.puts("✓ GPT-4o-mini model: #{gpt4o_mini.id}")

# GPT-4o-mini pricing (as of November 2024)
# $0.15 per 1M input tokens, $0.60 per 1M output tokens
import Ecto.Query

existing_price =
  Repo.one(
    from p in AIModelPrice,
      where: p.model_id == ^gpt4o_mini.id and is_nil(p.effective_until),
      limit: 1
  )

if is_nil(existing_price) do
  Repo.insert!(%AIModelPrice{
    model_id: gpt4o_mini.id,
    input_price_per_million: Decimal.new("0.15"),
    output_price_per_million: Decimal.new("0.60"),
    effective_from: ~U[2024-07-01 00:00:00Z]
  })

  IO.puts("✓ GPT-4o-mini pricing added")
else
  IO.puts("✓ GPT-4o-mini pricing already exists")
end

# GPT-4o (optional, for future use)
gpt4o =
  case Repo.get_by(AIModel, api_name: "gpt-4o") do
    nil ->
      Repo.insert!(%AIModel{
        provider_id: openai.id,
        name: "GPT-4o",
        api_name: "gpt-4o",
        is_active: true,
        is_default: false,
        capabilities: ["chat", "json_mode", "vision"]
      })

    existing ->
      existing
  end

IO.puts("✓ GPT-4o model: #{gpt4o.id}")

# GPT-4o pricing (as of November 2024)
# $2.50 per 1M input tokens, $10.00 per 1M output tokens
existing_gpt4o_price =
  Repo.one(
    from p in AIModelPrice,
      where: p.model_id == ^gpt4o.id and is_nil(p.effective_until),
      limit: 1
  )

if is_nil(existing_gpt4o_price) do
  Repo.insert!(%AIModelPrice{
    model_id: gpt4o.id,
    input_price_per_million: Decimal.new("2.50"),
    output_price_per_million: Decimal.new("10.00"),
    effective_from: ~U[2024-07-01 00:00:00Z]
  })

  IO.puts("✓ GPT-4o pricing added")
else
  IO.puts("✓ GPT-4o pricing already exists")
end

# ============================================================================
# Alert Thresholds
# ============================================================================

# Per-user monthly threshold ($10)
case Repo.get_by(AlertThreshold, name: "per_user_monthly") do
  nil ->
    Repo.insert!(%AlertThreshold{
      name: "per_user_monthly",
      threshold_cents: 1000,
      period: "monthly",
      scope: "per_user",
      is_active: true,
      notify_email: true,
      notify_dashboard: true
    })

    IO.puts("✓ Per-user monthly threshold ($10) created")

  _ ->
    IO.puts("✓ Per-user monthly threshold already exists")
end

# Total monthly threshold ($50)
case Repo.get_by(AlertThreshold, name: "total_monthly") do
  nil ->
    Repo.insert!(%AlertThreshold{
      name: "total_monthly",
      threshold_cents: 5000,
      period: "monthly",
      scope: "total",
      is_active: true,
      notify_email: true,
      notify_dashboard: true
    })

    IO.puts("✓ Total monthly threshold ($50) created")

  _ ->
    IO.puts("✓ Total monthly threshold already exists")
end

IO.puts("\n✅ Seeds completed!")
