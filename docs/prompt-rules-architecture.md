# Prompt Rules Architecture

**Status**: Future consideration
**Date**: 2025-11-26

## Problem Statement

The Mermaid syntax rules in `lib/diagram_forge/ai/prompts.ex` are duplicated across multiple prompts:
- `@diagram_system_prompt` - Brief rules for diagram generation
- `@fix_mermaid_syntax_prompt` - Detailed diagnostic rules for fixing broken diagrams

When rules need to be updated (e.g., after analyzing broken diagrams), changes must be made in multiple places, risking inconsistency.

## Current Implementation

Rules are hardcoded as module attributes in `DiagramForge.AI.Prompts`:

```elixir
@diagram_system_prompt """
  ...
  EDGE LABELS - MUST be quoted if they contain { } [ ] ( ):
  - -->|"{:ok, pid}"| not -->|{:ok, pid}|
  ...
"""

@fix_mermaid_syntax_prompt """
  ...
  3. EDGE LABELS WITH SPECIAL CHARS - MUST be quoted in Mermaid 11.x:
     WRONG: -->|{:ok, pid}|  or  -->|[1,2,3]|
     RIGHT: -->|"{:ok, pid}"|  or  -->|"[1,2,3]"|
     ANY edge label containing { } [ ] ( ) MUST be wrapped in quotes: |"..."|
  ...
"""
```

## Option 1: Module-based Composition (Simpler)

Keep rules in code but extract them to a dedicated module for DRY composition.

### Schema

```elixir
defmodule DiagramForge.AI.MermaidRules do
  @moduledoc """
  Single source of truth for Mermaid syntax rules.
  Each rule has a brief version (for generation) and detailed version (for fixing).
  """

  @rules [
    %{
      key: :node_brackets,
      category: :syntax,
      priority: 1,
      brief: "NODE LABELS - ALWAYS use proper syntax: A[\"text\"] not A\"text\"",
      detailed: """
      1. MISSING BRACKETS ON NODE LABELS:
         WRONG: A"text"  or  B"value"
         RIGHT: A["text"]  or  B["value"]
         Every node with a label MUST have brackets: ID["label"] not ID"label"
      """
    },
    %{
      key: :edge_labels_special_chars,
      category: :syntax,
      priority: 3,
      brief: "EDGE LABELS - MUST be quoted if they contain { } [ ] ( )",
      detailed: """
      3. EDGE LABELS WITH SPECIAL CHARS - MUST be quoted in Mermaid 11.x:
         WRONG: -->|{:ok, pid}|  or  -->|[1,2,3]|
         RIGHT: -->|"{:ok, pid}"|  or  -->|"[1,2,3]"|
      """
    },
    # ... more rules
  ]

  def all_rules, do: @rules

  def brief_rules do
    @rules
    |> Enum.sort_by(& &1.priority)
    |> Enum.map_join("\n\n", & &1.brief)
  end

  def detailed_rules do
    @rules
    |> Enum.sort_by(& &1.priority)
    |> Enum.map_join("\n\n", & &1.detailed)
  end

  def rules_by_category(category) do
    Enum.filter(@rules, & &1.category == category)
  end
end
```

### Usage in Prompts

```elixir
defmodule DiagramForge.AI.Prompts do
  alias DiagramForge.AI.MermaidRules

  @diagram_system_prompt """
  You generate small, interview-friendly technical diagrams in Mermaid syntax.
  Target Mermaid version: #{@mermaid_version}

  Constraints:
  - The diagram must fit on a single screen and stay readable.
  - Use at most 10 nodes and 15 edges.

  CRITICAL Mermaid 11.x syntax rules:

  #{MermaidRules.brief_rules()}

  Only output strictly valid JSON with the requested fields.
  """

  @fix_mermaid_syntax_prompt """
  The following Mermaid diagram has a syntax error...

  SCAN EVERY NODE AND EDGE LABEL for these issues:

  #{MermaidRules.detailed_rules()}

  Return ONLY valid JSON...
  """
end
```

### Pros
- Simple, no database overhead
- Compile-time validation
- Easy to test individual rules
- Single source of truth in code
- No migration needed

### Cons
- Requires code deploy to change rules
- Non-developers cannot adjust rules
- No rule effectiveness tracking

---

## Option 2: Database-backed Rules with ETS Cache (More Flexible)

Store rules in database, compose prompts dynamically, cache in ETS.

### Database Schema

```elixir
defmodule DiagramForge.AI.MermaidRule do
  use Ecto.Schema
  import Ecto.Changeset

  schema "mermaid_rules" do
    field :key, :string           # "edge_labels_special_chars"
    field :category, Ecto.Enum, values: [:syntax, :quotes, :brackets, :escaping, :special_chars]
    field :priority, :integer     # ordering within prompt
    field :enabled, :boolean, default: true
    field :brief, :string         # short version for generation
    field :detailed, :string      # full version with examples
    field :content_hash, :string  # SHA256 of brief+detailed for dedup detection

    timestamps()
  end

  def changeset(rule, attrs) do
    rule
    |> cast(attrs, [:key, :category, :priority, :enabled, :brief, :detailed])
    |> validate_required([:key, :category, :priority, :brief, :detailed])
    |> unique_constraint(:key)
    |> put_content_hash()
  end

  defp put_content_hash(changeset) do
    brief = get_field(changeset, :brief) || ""
    detailed = get_field(changeset, :detailed) || ""
    hash = :crypto.hash(:sha256, brief <> detailed) |> Base.encode16(case: :lower)
    put_change(changeset, :content_hash, hash)
  end
end
```

### Migration

```elixir
defmodule DiagramForge.Repo.Migrations.CreateMermaidRules do
  use Ecto.Migration

  def change do
    create table(:mermaid_rules) do
      add :key, :string, null: false
      add :category, :string, null: false
      add :priority, :integer, null: false, default: 100
      add :enabled, :boolean, null: false, default: true
      add :brief, :text, null: false
      add :detailed, :text, null: false
      add :content_hash, :string, null: false

      timestamps()
    end

    create unique_index(:mermaid_rules, [:key])
    create index(:mermaid_rules, [:category])
    create index(:mermaid_rules, [:enabled, :priority])
  end
end
```

### ETS Cache Module

```elixir
defmodule DiagramForge.AI.RulesCache do
  use GenServer
  require Logger

  @table :mermaid_rules_cache
  @refresh_interval :timer.minutes(5)

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def init(_) do
    :ets.new(@table, [:named_table, :set, :public, read_concurrency: true])
    refresh_cache()
    schedule_refresh()
    {:ok, %{}}
  end

  # Public API
  def brief_rules do
    case :ets.lookup(@table, :brief_rules) do
      [{:brief_rules, rules}] -> rules
      [] -> refresh_and_get(:brief_rules)
    end
  end

  def detailed_rules do
    case :ets.lookup(@table, :detailed_rules) do
      [{:detailed_rules, rules}] -> rules
      [] -> refresh_and_get(:detailed_rules)
    end
  end

  def invalidate do
    GenServer.cast(__MODULE__, :refresh)
  end

  # Server callbacks
  def handle_cast(:refresh, state) do
    refresh_cache()
    {:noreply, state}
  end

  def handle_info(:refresh, state) do
    refresh_cache()
    schedule_refresh()
    {:noreply, state}
  end

  defp refresh_cache do
    rules = DiagramForge.AI.MermaidRules.list_enabled()

    brief = rules |> Enum.map_join("\n\n", & &1.brief)
    detailed = rules |> Enum.map_join("\n\n", & &1.detailed)

    :ets.insert(@table, {:brief_rules, brief})
    :ets.insert(@table, {:detailed_rules, detailed})

    Logger.debug("Mermaid rules cache refreshed with #{length(rules)} rules")
  end

  defp refresh_and_get(key) do
    refresh_cache()
    [{^key, value}] = :ets.lookup(@table, key)
    value
  end

  defp schedule_refresh do
    Process.send_after(self(), :refresh, @refresh_interval)
  end
end
```

### Context Module

```elixir
defmodule DiagramForge.AI.MermaidRules do
  import Ecto.Query
  alias DiagramForge.Repo
  alias DiagramForge.AI.MermaidRule

  def list_enabled do
    MermaidRule
    |> where([r], r.enabled == true)
    |> order_by([r], asc: r.priority)
    |> Repo.all()
  end

  def get_rule!(key), do: Repo.get_by!(MermaidRule, key: key)

  def create_rule(attrs) do
    %MermaidRule{}
    |> MermaidRule.changeset(attrs)
    |> Repo.insert()
    |> tap(fn _ -> DiagramForge.AI.RulesCache.invalidate() end)
  end

  def update_rule(%MermaidRule{} = rule, attrs) do
    rule
    |> MermaidRule.changeset(attrs)
    |> Repo.update()
    |> tap(fn _ -> DiagramForge.AI.RulesCache.invalidate() end)
  end

  def toggle_rule(%MermaidRule{} = rule) do
    update_rule(rule, %{enabled: !rule.enabled})
  end

  def find_duplicate(brief, detailed) do
    hash = :crypto.hash(:sha256, brief <> detailed) |> Base.encode16(case: :lower)
    Repo.get_by(MermaidRule, content_hash: hash)
  end
end
```

### Admin UI (Backpex Resource)

```elixir
defmodule DiagramForgeWeb.Admin.MermaidRuleResource do
  use Backpex.LiveResource,
    layout: {DiagramForgeWeb.Layouts, :admin},
    schema: DiagramForge.AI.MermaidRule,
    repo: DiagramForge.Repo,
    update_changeset: &DiagramForge.AI.MermaidRule.changeset/2,
    create_changeset: &DiagramForge.AI.MermaidRule.changeset/2

  @impl Backpex.LiveResource
  def singular_name, do: "Mermaid Rule"

  @impl Backpex.LiveResource
  def plural_name, do: "Mermaid Rules"

  @impl Backpex.LiveResource
  def fields do
    [
      key: %{module: Backpex.Fields.Text, label: "Key"},
      category: %{module: Backpex.Fields.Select, label: "Category",
        options: [Syntax: :syntax, Quotes: :quotes, Brackets: :brackets,
                  Escaping: :escaping, Special: :special_chars]},
      priority: %{module: Backpex.Fields.Number, label: "Priority"},
      enabled: %{module: Backpex.Fields.Boolean, label: "Enabled"},
      brief: %{module: Backpex.Fields.Textarea, label: "Brief (Generation)"},
      detailed: %{module: Backpex.Fields.Textarea, label: "Detailed (Fix)"}
    ]
  end
end
```

### Pros
- Single source of truth in database
- Admin UI for non-developers to adjust rules
- Can A/B test different rule sets
- Track rule changes over time (audit log)
- Content hash prevents accidental duplicates
- ETS cache ensures performance

### Cons
- More complexity (DB, cache, GenServer)
- Migration needed to seed initial rules
- Cache invalidation considerations
- Harder to test (need DB fixtures)

---

## Recommendation

**For now**: Keep the current hardcoded approach. The rules have just been updated based on broken diagram analysis, and they should be stable for a while.

**When to revisit**:
- If rules need frequent adjustment based on validation results
- If non-developers need to tune prompts
- If you want to track which rules correlate with fewer broken diagrams
- If you add more prompt types that share the same rules

**If revisiting**: Start with Option 1 (module-based composition) as it's simpler and gives the main benefit (DRY) without database complexity. Move to Option 2 only if admin-editable rules become a real requirement.

---

## Related Files

- `lib/diagram_forge/ai/prompts.ex` - Current prompt definitions
- `docs/broken_diagrams_analysis.md` - Analysis that drove recent rule updates
- `scripts/validate_mermaid.mjs` - Validation script to test rule effectiveness
