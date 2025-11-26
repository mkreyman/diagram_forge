defmodule DiagramForge.Fixtures do
  @moduledoc """
  This module defines test helpers for creating entities for testing.
  It consolidates all fixtures into a single module with a consistent interface.
  """

  alias DiagramForge.Accounts.User
  alias DiagramForge.AI.Prompt
  alias DiagramForge.Diagrams.{Diagram, Document, SavedFilter}
  alias DiagramForge.Repo

  alias DiagramForge.Usage.{
    AIModel,
    AIModelPrice,
    AIProvider,
    Alert,
    AlertThreshold,
    DailyAggregate,
    TokenUsage
  }

  @doc """
  Creates a record in the database based on the given schema and attributes.

  This is the main fixture function that builds a struct and inserts it.
  """
  def fixture(schema, attrs \\ %{}) do
    schema
    |> build(attrs)
    |> Repo.insert!()
  end

  @doc """
  Builds a struct without inserting it into the database.
  """
  def build(:document, attrs) do
    user = attrs[:user] || fixture(:user)

    %Document{user_id: user.id}
    |> Document.changeset(
      attrs
      |> Enum.into(%{
        title: "Test Document #{System.unique_integer([:positive])}",
        source_type: :markdown,
        path: "/tmp/test-#{System.unique_integer([:positive])}.md",
        status: :uploaded
      })
    )
  end

  def build(:diagram, attrs) do
    document = attrs[:document]

    base_attrs = %{
      title: "Test Diagram #{System.unique_integer([:positive])}",
      tags: ["test"],
      format: :mermaid,
      diagram_source: "flowchart TD\n  A[Start] --> B[End]",
      summary: "A test diagram"
    }

    base_attrs =
      if document do
        Map.put(base_attrs, :document_id, document.id)
      else
        base_attrs
      end

    %Diagram{}
    |> Diagram.changeset(
      attrs
      |> Enum.into(base_attrs)
    )
  end

  def build(:saved_filter, attrs) do
    user = attrs[:user] || fixture(:user)

    %SavedFilter{}
    |> SavedFilter.changeset(
      attrs
      |> Enum.into(%{
        user_id: user.id,
        name: "Test Filter #{System.unique_integer([:positive])}",
        tag_filter: ["elixir", "test"],
        is_pinned: true,
        sort_order: 0
      })
    )
  end

  def build(:diagram_with_tags, attrs) do
    default_tags = ["elixir", "phoenix", "test"]
    attrs = Map.put_new(attrs, :tags, default_tags)
    build(:diagram, attrs)
  end

  def build(:user, attrs) do
    unique_id = System.unique_integer([:positive])

    %User{}
    |> User.changeset(
      attrs
      |> Enum.into(%{
        email: "user#{unique_id}@example.com",
        name: "Test User #{unique_id}",
        provider: "github",
        provider_uid: "github_uid_#{unique_id}",
        provider_token: "test_token_#{unique_id}"
      })
    )
  end

  def build(:prompt, attrs) do
    unique_id = System.unique_integer([:positive])

    %Prompt{}
    |> Prompt.changeset(
      attrs
      |> Enum.into(%{
        key: "test_prompt_#{unique_id}",
        content: "Test prompt content #{unique_id}",
        description: "Test prompt description"
      })
    )
  end

  def build(:ai_provider, attrs) do
    unique_id = System.unique_integer([:positive])

    %AIProvider{}
    |> AIProvider.changeset(
      attrs
      |> Enum.into(%{
        name: "Test Provider #{unique_id}",
        slug: "test-provider-#{unique_id}",
        is_active: true
      })
    )
  end

  def build(:ai_model, attrs) do
    attrs = Enum.into(attrs, %{})
    provider = attrs[:provider] || fixture(:ai_provider)
    unique_id = System.unique_integer([:positive])

    %AIModel{}
    |> AIModel.changeset(
      attrs
      |> Map.drop([:provider])
      |> Enum.into(%{
        provider_id: provider.id,
        name: "Test Model #{unique_id}",
        api_name: "test-model-#{unique_id}",
        capabilities: ["text"],
        is_active: true,
        is_default: false
      })
    )
  end

  def build(:ai_model_price, attrs) do
    attrs = Enum.into(attrs, %{})
    model = attrs[:model] || fixture(:ai_model)

    %AIModelPrice{}
    |> AIModelPrice.changeset(
      attrs
      |> Map.drop([:model])
      |> Enum.into(%{
        model_id: model.id,
        input_price_per_million: Decimal.new("1.00"),
        output_price_per_million: Decimal.new("2.00"),
        effective_from: DateTime.utc_now() |> DateTime.add(-86_400, :second)
      })
    )
  end

  def build(:token_usage, attrs) do
    attrs = Enum.into(attrs, %{})
    user = attrs[:user] || fixture(:user)
    model = attrs[:model] || fixture(:ai_model)

    %TokenUsage{}
    |> TokenUsage.changeset(
      attrs
      |> Map.drop([:user, :model])
      |> Enum.into(%{
        user_id: user.id,
        model_id: model.id,
        operation: "diagram_generation",
        input_tokens: 1000,
        output_tokens: 500,
        total_tokens: 1500,
        cost_cents: 100,
        metadata: %{}
      })
    )
  end

  def build(:daily_aggregate, attrs) do
    attrs = Enum.into(attrs, %{})
    user = attrs[:user]
    model = attrs[:model] || fixture(:ai_model)

    base = %{
      model_id: model.id,
      date: Date.utc_today(),
      input_tokens: 10_000,
      output_tokens: 5000,
      total_tokens: 15_000,
      cost_cents: 1000,
      request_count: 10
    }

    base = if user, do: Map.put(base, :user_id, user.id), else: base

    %DailyAggregate{}
    |> DailyAggregate.changeset(
      attrs
      |> Map.drop([:user, :model])
      |> Enum.into(base)
    )
  end

  def build(:alert_threshold, attrs) do
    attrs = Enum.into(attrs, %{})

    %AlertThreshold{}
    |> AlertThreshold.changeset(
      attrs
      |> Enum.into(%{
        name: "Test Threshold #{System.unique_integer([:positive])}",
        threshold_cents: 10_000,
        period: "daily",
        scope: "total",
        is_active: true
      })
    )
  end

  def build(:alert, attrs) do
    attrs = Enum.into(attrs, %{})
    threshold = attrs[:threshold] || fixture(:alert_threshold)

    %Alert{}
    |> Alert.changeset(
      attrs
      |> Map.drop([:threshold])
      |> Enum.into(%{
        threshold_id: threshold.id,
        period_start: Date.utc_today() |> Date.beginning_of_month(),
        period_end: Date.utc_today() |> Date.end_of_month(),
        amount_cents: 15_000
      })
    )
  end
end
