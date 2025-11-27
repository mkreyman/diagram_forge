# Script for populating the database with sample API usage data.
# Run via: mix seed.usage
#
# This creates realistic usage data across multiple days, users, and models
# to demonstrate the Usage Dashboard features.

import Ecto.Query
alias DiagramForge.Repo
alias DiagramForge.Accounts.User
alias DiagramForge.Usage
alias DiagramForge.Usage.{AIProvider, AIModel, DailyAggregate, TokenUsage}

IO.puts("Seeding API usage data...")

# ============================================================================
# Ensure AI providers and models exist (run seeds.exs first if needed)
# ============================================================================

openai = Repo.get_by(AIProvider, slug: "openai")

unless openai do
  IO.puts("Error: OpenAI provider not found. Run `mix run priv/repo/seeds.exs` first.")
  System.halt(1)
end

gpt4o_mini = Repo.get_by(AIModel, api_name: "gpt-4o-mini")
gpt4o = Repo.get_by(AIModel, api_name: "gpt-4o")

unless gpt4o_mini do
  IO.puts("Error: GPT-4o-mini model not found. Run `mix run priv/repo/seeds.exs` first.")
  System.halt(1)
end

IO.puts("Using models: #{gpt4o_mini.name}, #{gpt4o && gpt4o.name || "N/A"}")

# ============================================================================
# Clear existing usage data (but keep providers/models/prices)
# ============================================================================

IO.puts("Clearing existing usage data...")
Repo.delete_all(TokenUsage)
Repo.delete_all(DailyAggregate)

# ============================================================================
# Create sample users
# ============================================================================

IO.puts("Creating sample users...")

# Delete any existing seed users first
Repo.delete_all(from u in User, where: u.email in ["alice@example.com", "bob@example.com", "charlie@example.com"])

users =
  for {email, name} <- [
        {"alice@example.com", "Alice Developer"},
        {"bob@example.com", "Bob Engineer"},
        {"charlie@example.com", "Charlie Architect"}
      ] do
    %User{}
    |> User.changeset(%{
      email: email,
      name: name,
      provider: "github",
      provider_uid: "seed_#{String.replace(email, "@example.com", "")}",
      provider_token: "seed_token_#{:rand.uniform(100_000)}",
      show_public_diagrams: true
    })
    |> Repo.insert!()
  end

[alice, bob, charlie] = users
IO.puts("Created #{length(users)} users")

# ============================================================================
# Generate usage data for the past 30 days
# ============================================================================

IO.puts("Generating usage data for the past 30 days...")

today = Date.utc_today()

# Usage patterns per user (to create varied, realistic data)
# {user, model, daily_requests_range, operations}
usage_patterns = [
  # Alice: Heavy user, mostly gpt-4o-mini for diagram generation
  {alice, gpt4o_mini, 15..40, ["diagram_generation", "concept_extraction", "fix_syntax"]},
  # Bob: Moderate user, mix of models
  {bob, gpt4o_mini, 5..20, ["diagram_generation", "concept_extraction"]},
  {bob, gpt4o, 1..5, ["diagram_generation"]},
  # Charlie: Light user, occasional usage
  {charlie, gpt4o_mini, 0..10, ["diagram_generation"]}
]

# Token ranges based on operation type
token_ranges = %{
  "concept_extraction" => {800..2000, 200..500},
  "diagram_generation" => {1000..3000, 300..800},
  "fix_syntax" => {500..1500, 200..400}
}

for day_offset <- 30..0//-1 do
  date = Date.add(today, -day_offset)

  # Skip some weekend days for realism
  day_of_week = Date.day_of_week(date)
  weekend_factor = if day_of_week in [6, 7], do: 0.3, else: 1.0

  for {user, model, request_range, operations} <- usage_patterns do
    # Skip if model doesn't exist (gpt4o might be nil)
    if model do
      # Adjust request count based on day of week
      base_requests = Enum.random(request_range)
      num_requests = round(base_requests * weekend_factor)

      if num_requests > 0 do
        # Generate aggregated data for this user/model/day
        {total_input, total_output} =
          for _ <- 1..num_requests, reduce: {0, 0} do
            {input_acc, output_acc} ->
              operation = Enum.random(operations)
              {input_range, output_range} = token_ranges[operation]
              input_tokens = Enum.random(input_range)
              output_tokens = Enum.random(output_range)
              {input_acc + input_tokens, output_acc + output_tokens}
          end

        # Insert daily aggregate directly (more efficient than individual records)
        Repo.insert!(%DailyAggregate{
          user_id: user.id,
          model_id: model.id,
          date: date,
          request_count: num_requests,
          input_tokens: total_input,
          output_tokens: total_output,
          total_tokens: total_input + total_output,
          cost_cents: 0  # Will be calculated at display time
        })
      end
    end
  end
end

# ============================================================================
# Summary
# ============================================================================

total_aggregates = Repo.aggregate(DailyAggregate, :count, :id)
total_requests = Repo.aggregate(DailyAggregate, :sum, :request_count) || 0
total_input_tokens = Repo.aggregate(DailyAggregate, :sum, :input_tokens) || 0
total_output_tokens = Repo.aggregate(DailyAggregate, :sum, :output_tokens) || 0

# Calculate cost using the new function
summary = Usage.get_summary_for_range(Date.add(today, -30), today)

IO.puts("")
IO.puts("=" |> String.duplicate(50))
IO.puts("Usage Data Seeding Complete!")
IO.puts("=" |> String.duplicate(50))
IO.puts("")
IO.puts("Daily aggregates created: #{total_aggregates}")
IO.puts("Total requests: #{total_requests}")
IO.puts("Total input tokens: #{Number.Delimit.number_to_delimited(total_input_tokens, precision: 0)}")
IO.puts("Total output tokens: #{Number.Delimit.number_to_delimited(total_output_tokens, precision: 0)}")
IO.puts("Estimated cost: $#{Usage.format_cents(summary.cost_cents)}")
IO.puts("")
IO.puts("Users created:")
for user <- users do
  IO.puts("  - #{user.email}")
end
IO.puts("")
IO.puts("View the dashboard at: /admin/usage/dashboard")

# ============================================================================
# Moderation Queue Test Data
# ============================================================================

IO.puts("")
IO.puts("Seeding moderation queue data...")

alias DiagramForge.Diagrams.{Document, Diagram}
alias DiagramForge.Content.ModerationLog

# Create a document for moderation test diagrams
mod_document =
  case Repo.get_by(Document, title: "Moderation Test Diagrams") do
    nil ->
      %Document{user_id: alice.id}
      |> Document.changeset(%{
        title: "Moderation Test Diagrams",
        source_type: :markdown,
        path: "docs/moderation-test.md",
        status: :ready,
        raw_text: "Test diagrams for moderation queue testing."
      })
      |> Repo.insert!()

    existing ->
      existing
  end

# Helper to create diagrams with moderation status
create_moderated_diagram = fn title, source, status, reason, _user ->
  diagram =
    %Diagram{}
    |> Diagram.changeset(%{
      document_id: mod_document.id,
      title: title,
      tags: ["test", "moderation"],
      diagram_source: source,
      summary: "Test diagram for moderation status: #{status}",
      visibility: :public
    })
    |> Repo.insert!()

  # Update moderation status
  diagram
  |> Diagram.moderation_changeset(%{
    moderation_status: status,
    moderation_reason: reason,
    moderated_at: DateTime.utc_now()
  })
  |> Repo.update!()

  # Create moderation log
  action =
    case status do
      :approved -> "ai_approve"
      :rejected -> "ai_reject"
      :manual_review -> "ai_manual_review"
      _ -> "ai_approve"
    end

  %ModerationLog{}
  |> ModerationLog.changeset(%{
    diagram_id: diagram.id,
    action: action,
    previous_status: "pending",
    new_status: to_string(status),
    reason: reason,
    ai_confidence: :rand.uniform() * 0.5 + 0.5,
    ai_flags: if(status == :manual_review, do: ["suspicious_output"], else: [])
  })
  |> Repo.insert!()

  diagram
end

# Clear existing moderation test diagrams
Repo.delete_all(from d in Diagram, where: d.document_id == ^mod_document.id)

# Create diagrams pending manual review (these show in the moderation queue)
IO.puts("Creating diagrams for manual review...")

create_moderated_diagram.(
  "Suspicious System Architecture",
  """
  flowchart TD
      A[User Input] --> B[Process Data]
      B --> C[Store Results]
      C --> D[Return Response]
  """,
  :manual_review,
  "AI flagged for review: Content contains unusual patterns that require human verification",
  alice
)

create_moderated_diagram.(
  "Workflow with Flagged Content",
  """
  sequenceDiagram
      participant U as User
      participant S as Server
      U->>S: Submit Request
      S-->>U: Process and Respond
  """,
  :manual_review,
  "AI flagged for review: Suspicious output detected - confidence below threshold",
  bob
)

create_moderated_diagram.(
  "Data Pipeline Review Required",
  """
  flowchart LR
      Input[Data Source] --> Transform[ETL Process]
      Transform --> Load[Data Warehouse]
      Load --> Analytics[BI Dashboard]
  """,
  :manual_review,
  "AI flagged for review: Content may contain embedded instructions",
  charlie
)

create_moderated_diagram.(
  "API Integration Needs Review",
  """
  flowchart TD
      Client[Mobile App] --> API[REST API]
      API --> Auth[Auth Service]
      API --> DB[(Database)]
  """,
  :manual_review,
  "AI flagged for review: Output validation detected potential injection pattern",
  alice
)

create_moderated_diagram.(
  "Microservices Architecture Flagged",
  """
  flowchart LR
      GW[API Gateway] --> S1[Service A]
      GW --> S2[Service B]
      S1 --> MQ[Message Queue]
      S2 --> MQ
  """,
  :manual_review,
  "AI flagged for review: Low confidence score (0.42) - requires human judgment",
  bob
)

# Create some approved diagrams
IO.puts("Creating approved diagrams...")

create_moderated_diagram.(
  "Clean Architecture Diagram",
  """
  flowchart TD
      UI[Presentation Layer] --> App[Application Layer]
      App --> Domain[Domain Layer]
      Domain --> Infra[Infrastructure]
  """,
  :approved,
  "AI approved: Clean technical content with high confidence",
  alice
)

create_moderated_diagram.(
  "Database Schema - Approved",
  """
  erDiagram
      USER ||--o{ ORDER : places
      ORDER ||--|{ LINE_ITEM : contains
      PRODUCT ||--o{ LINE_ITEM : includes
  """,
  :approved,
  "AI approved: Standard database diagram, no policy violations",
  bob
)

# Create some rejected diagrams
IO.puts("Creating rejected diagrams...")

create_moderated_diagram.(
  "Rejected Diagram - Policy Violation",
  """
  flowchart TD
      A[Step 1] --> B[Step 2]
      B --> C[Step 3]
  """,
  :rejected,
  "AI rejected: Content violated spam policy - promotional material detected",
  charlie
)

create_moderated_diagram.(
  "Another Rejected Example",
  """
  flowchart LR
      X[Input] --> Y[Process]
      Y --> Z[Output]
  """,
  :rejected,
  "AI rejected: Inappropriate content detected in diagram labels",
  alice
)

# Summary
pending_review = Repo.aggregate(from(d in Diagram, where: d.moderation_status == :manual_review), :count)
approved_count = Repo.aggregate(from(d in Diagram, where: d.moderation_status == :approved), :count)
rejected_count = Repo.aggregate(from(d in Diagram, where: d.moderation_status == :rejected), :count)

IO.puts("")
IO.puts("=" |> String.duplicate(50))
IO.puts("Moderation Queue Data Complete!")
IO.puts("=" |> String.duplicate(50))
IO.puts("")
IO.puts("Pending review: #{pending_review}")
IO.puts("Approved: #{approved_count}")
IO.puts("Rejected: #{rejected_count}")
IO.puts("")
IO.puts("View the moderation queue at: /admin/moderation")
