# Script for populating the database with sample diagrams.
# Run via: mix seed.diagrams

import Ecto.Query
alias DiagramForge.Repo
alias DiagramForge.Accounts.User
alias DiagramForge.Diagrams
alias DiagramForge.Diagrams.{Document, Diagram, UserDiagram, SavedFilter}

# Clear existing diagram data in correct order (respecting foreign keys)
# Note: We preserve the seed user if they already exist
IO.puts("Clearing existing diagram data...")
Repo.delete_all(UserDiagram)
Repo.delete_all(SavedFilter)
Repo.delete_all(Diagram)
Repo.delete_all(Document)

# Get or create the seed user for diagram ownership
IO.puts("Getting or creating seed user...")

seed_user =
  case Repo.get_by(User, email: "seed@example.com") do
    nil ->
      %User{}
      |> User.changeset(%{
        email: "seed@example.com",
        name: "Seed User",
        provider: "github",
        provider_uid: "seed_user_12345",
        provider_token: "seed_token",
        show_public_diagrams: true
      })
      |> Repo.insert!()

    existing ->
      existing
  end

IO.puts("Using seed user with ID: #{seed_user.id}")

# Create a seed document (owned by seed user)
IO.puts("Creating seed document...")

document =
  %Document{user_id: seed_user.id}
  |> Document.changeset(%{
    title: "Distributed Systems & ML Architecture Patterns",
    source_type: :markdown,
    path: "docs/technical-patterns.md",
    status: :ready,
    raw_text: """
    Technical patterns for building distributed systems with Elixir/OTP,
    event-driven architectures with Kafka, ML model serving, and database optimization.
    """
  })
  |> Repo.insert!()

IO.puts("Document created with ID: #{document.id}")

# Helper function to create diagrams and assign ownership
create_diagram = fn title, tags, mermaid, summary, notes, visibility ->
  diagram =
    %Diagram{}
    |> Diagram.changeset(%{
      document_id: document.id,
      title: title,
      tags: tags,
      diagram_source: mermaid,
      summary: summary,
      notes_md: notes,
      visibility: visibility
    })
    |> Repo.insert!()

  # Assign ownership to seed user
  Diagrams.assign_diagram_to_user(diagram.id, seed_user.id, true)

  diagram
end

IO.puts("Creating diagrams...")

# GenServer Patterns diagrams
create_diagram.(
  "GenServer Call vs Cast",
  ["genserver", "concurrency", "otp", "elixir"],
  """
  sequenceDiagram
      participant C as Client
      participant G as GenServer
      C->>+G: call(:get_state)
      G-->>-C: {:ok, state}
      Note over C,G: Synchronous - blocks client
      C-)+G: cast(:update, val)
      Note over G: Asynchronous - returns immediately
      G->>G: handle_cast
      Note over G: Updates state without reply
  """,
  "Compares synchronous GenServer.call/3 which blocks the caller until a reply is received, versus asynchronous GenServer.cast/2 which returns immediately without waiting.",
  """
  - `call/3` blocks the caller and expects a reply
  - `cast/2` fires and forgets, useful for updates that don't need confirmation
  - Use call for queries, cast for commands that don't need acknowledgment
  - Calls can timeout if the GenServer is busy
  """,
  :public
)

create_diagram.(
  "GenServer State Management",
  ["genserver", "state", "functional", "elixir"],
  """
  flowchart TD
      A[Client Request] --> B{handle_call/3}
      B --> C[Read Current State]
      C --> D[Compute New State]
      D --> E[Return Reply + New State]
      E --> F[GenServer updates state]
      F --> G[Ready for next request]
  """,
  "Shows how GenServer maintains state immutably by returning new state from each callback.",
  """
  - State is passed as the last argument to callbacks
  - Callbacks return `{:reply, response, new_state}` or `{:noreply, new_state}`
  - State transformations are pure functions
  - Old state is garbage collected after callback returns
  """,
  :public
)

create_diagram.(
  "GenServer Timeout Patterns",
  ["genserver", "timeout", "reliability", "elixir"],
  """
  sequenceDiagram
      participant C as Client
      participant G as GenServer
      C->>+G: call(:slow_operation, 5000)
      Note over G: Processing...
      alt Completes in time
          G-->>-C: {:ok, result}
      else Timeout after 5s
          G--xC: :timeout error
          Note over C: Client can retry or fail gracefully
      end
  """,
  "Demonstrates timeout handling in GenServer calls to prevent indefinite blocking.",
  """
  - Default timeout is 5 seconds
  - Can specify custom timeout: `GenServer.call(pid, :msg, 10_000)`
  - Server continues processing even after timeout
  - Client should handle `:timeout` error appropriately
  """,
  :unlisted
)

create_diagram.(
  "GenServer Initialization Flow",
  ["genserver", "initialization", "otp", "elixir"],
  """
  sequenceDiagram
      participant S as Supervisor
      participant G as GenServer
      participant D as Database
      S->>+G: start_link(args)
      G->>G: init(args)
      G->>D: Load initial data
      D-->>G: Data
      alt Initialization succeeds
          G-->>-S: {:ok, pid}
          Note over S: Child added to supervisor
      else Initialization fails
          G--xS: {:error, reason}
          Note over S: Supervisor may retry based on strategy
      end
  """,
  "Shows the GenServer initialization sequence and how failures are handled during startup.",
  """
  - `init/1` is called synchronously during `start_link`
  - Heavy initialization work blocks supervisor startup
  - Use `{:continue, work}` to defer heavy work to `handle_continue/2`
  - Return `{:stop, reason}` to prevent server from starting
  """,
  :public
)

# OTP Supervision diagrams
create_diagram.(
  "Supervision Tree Structure",
  ["supervisor", "otp", "architecture", "elixir"],
  """
  flowchart TD
      A[Application] --> B[Top Supervisor]
      B --> C[Cache Manager]
      B --> D[Worker Supervisor]
      B --> E[Database Pool]
      D --> F[Worker 1]
      D --> G[Worker 2]
      D --> H[Worker 3]
      style B fill:#4a5568
      style D fill:#4a5568
  """,
  "Illustrates a typical OTP supervision tree with multiple levels of supervisors organizing workers.",
  """
  - Supervisors form a tree structure
  - Each supervisor manages its immediate children
  - Workers are leaf nodes (GenServers, Tasks, etc.)
  - Supervisors can supervise other supervisors
  """,
  :public
)

create_diagram.(
  "Supervisor Restart Strategies",
  ["supervisor", "fault-tolerance", "strategies", "elixir"],
  """
  flowchart LR
      A[Child Crashes] --> B{Restart Strategy}
      B -->|one_for_one| C[Restart only crashed child]
      B -->|one_for_all| D[Restart all children]
      B -->|rest_for_one| E[Restart crashed + children started after it]
      style B fill:#d69e2e
  """,
  "Compares the three main supervisor restart strategies and when each crashed child triggers restarts.",
  """
  - `:one_for_one` - Only restart the crashed process (most common)
  - `:one_for_all` - Restart all children if any crashes (use when dependent)
  - `:rest_for_one` - Restart crashed child and all started after it (ordered dependencies)
  - Choose based on dependencies between children
  """,
  :public
)

create_diagram.(
  "Process Crash and Restart Flow",
  ["supervisor", "crash", "restart", "elixir"],
  """
  sequenceDiagram
      participant S as Supervisor
      participant W as Worker
      participant N as New Worker
      W->>W: Crash!
      W--xS: :EXIT signal
      Note over S: Detects child exit
      S->>S: Check restart strategy
      alt Under max_restarts threshold
          S->>+N: start_link(args)
          N-->>-S: {:ok, pid}
          Note over S: Worker restored
      else Exceeded max_restarts
          S->>S: Shutdown
          S-->>App: Escalate to parent supervisor
      end
  """,
  "Shows how supervisors detect crashes and restart workers, with escalation if restarts exceed limits.",
  """
  - Supervisor monitors all children via process links
  - Receives `:EXIT` signal when child crashes
  - Attempts restart based on strategy
  - If `max_restarts` exceeded in `max_seconds`, supervisor shuts down
  """,
  :unlisted
)

# Event-Driven Processing diagrams
create_diagram.(
  "Kafka Topic and Consumer Groups",
  ["kafka", "messaging", "streaming"],
  """
  flowchart LR
      P[Producer] --> T[Topic: orders]
      T --> |Partition 0| C1[Consumer A - Group 1]
      T --> |Partition 1| C2[Consumer B - Group 1]
      T --> |Partition 2| C3[Consumer C - Group 1]
      T --> |All Partitions| C4[Consumer - Group 2]
      style T fill:#d69e2e
  """,
  "Shows how Kafka topics with multiple partitions distribute messages across consumers in a group.",
  """
  - Each partition is consumed by one consumer in a group
  - Multiple consumer groups can read the same topic independently
  - Partitions enable parallel processing
  - Kafka tracks offset per consumer group per partition
  """,
  :public
)

create_diagram.(
  "Broadway Pipeline Processing",
  ["broadway", "elixir", "pipeline", "kafka"],
  """
  flowchart LR
      K[Kafka] --> P[Producer]
      P --> B1[Batch 1]
      P --> B2[Batch 2]
      P --> B3[Batch 3]
      B1 --> Proc1[Process]
      B2 --> Proc2[Process]
      B3 --> Proc3[Process]
      Proc1 --> Ack[Acknowledge]
      Proc2 --> Ack
      Proc3 --> Ack
      style P fill:#4a5568
      style Ack fill:#48bb78
  """,
  "Illustrates Broadway's concurrent batch processing pipeline for consuming Kafka events.",
  """
  - Broadway manages concurrent processors
  - Events are batched automatically
  - Built-in backpressure prevents overload
  - Acknowledgments are handled automatically
  """,
  :public
)

create_diagram.(
  "Event Sourcing Pattern",
  ["event-sourcing", "cqrs", "architecture"],
  """
  flowchart TD
      C[Command] --> A[Aggregate]
      A --> E1[Event 1]
      A --> E2[Event 2]
      E1 --> ES[Event Store/Kafka]
      E2 --> ES
      ES --> P1[Projection 1: Read Model]
      ES --> P2[Projection 2: Analytics]
      ES --> P3[Projection 3: Notifications]
      style ES fill:#d69e2e
  """,
  "Shows how event sourcing stores all state changes as events, which are then projected into different read models.",
  """
  - All state changes are captured as immutable events
  - Events are the source of truth
  - Multiple projections create different views of the data
  - Can replay events to rebuild state or create new projections
  """,
  :unlisted
)

create_diagram.(
  "At-Least-Once Delivery Semantics",
  ["kafka", "reliability", "delivery"],
  """
  sequenceDiagram
      participant K as Kafka
      participant C as Consumer
      participant DB as Database
      K->>+C: Message 1
      C->>DB: Process & Store
      DB-->>C: Success
      C->>K: Commit Offset
      Note over K,C: Happy path
      K->>+C: Message 2
      C->>DB: Process & Store
      DB--xC: Failure
      Note over C: Don't commit offset
      C->>C: Retry
      C->>DB: Process & Store (duplicate)
      DB-->>C: Success
      C->>K: Commit Offset
  """,
  "Demonstrates Kafka's at-least-once delivery where messages may be reprocessed on failure.",
  """
  - Consumer commits offset only after successful processing
  - On failure, message is redelivered from last committed offset
  - Processing must be idempotent to handle duplicates
  - Use unique IDs to detect and skip duplicate messages
  """,
  :public
)

# ML Model Serving diagrams
create_diagram.(
  "Two-Tier Caching Strategy",
  ["caching", "ets", "redis", "ml"],
  """
  flowchart TD
      R[Request] --> E{ETS Cache Hit?}
      E -->|Yes| RE1[Return from ETS]
      E -->|No| R1{Redis Cache Hit?}
      R1 -->|Yes| RE2[Return from Redis + Update ETS]
      R1 -->|No| ML[Call ML Model]
      ML --> U[Update Redis + ETS]
      U --> RET[Return Prediction]
      style E fill:#48bb78
      style R1 fill:#ed8936
      style ML fill:#e53e3e
  """,
  "Shows a two-level caching strategy using fast ETS for hot data and Redis for shared cache across nodes.",
  """
  - ETS provides in-memory cache within a single node (microseconds)
  - Redis provides shared cache across nodes (milliseconds)
  - ML inference is slowest fallback (hundreds of milliseconds)
  - Cache keys should include feature versions to avoid stale predictions
  """,
  :public
)

create_diagram.(
  "Circuit Breaker for ML Service",
  ["circuit-breaker", "reliability", "resilience", "ml"],
  """
  stateDiagram-v2
      [*] --> Closed
      Closed --> Open: Failures exceed threshold
      Open --> HalfOpen: After timeout
      HalfOpen --> Closed: Success
      HalfOpen --> Open: Failure
      note right of Closed: All requests pass through
      note right of Open: Fail fast, return fallback
      note right of HalfOpen: Test with limited requests
  """,
  "Circuit breaker pattern prevents cascading failures when ML service is down by failing fast after detecting issues.",
  """
  - **Closed**: Normal operation, requests flow through
  - **Open**: Too many failures, reject requests immediately with fallback
  - **Half-Open**: After cooldown, test if service recovered
  - Prevents overwhelming a failing service with requests
  """,
  :unlisted
)

create_diagram.(
  "Edge vs Cloud Inference Trade-offs",
  ["edge", "cloud", "architecture", "ml"],
  """
  flowchart LR
      R[Request] --> D{Latency Critical?}
      D -->|Yes| Edge[Edge Inference]
      D -->|No| Cloud[Cloud Inference]
      Edge --> E1[Lower Latency<br/>Limited Model Size<br/>Higher Cost per Node]
      Cloud --> C1[Higher Latency<br/>Larger Models<br/>Lower Cost at Scale]
      style Edge fill:#48bb78
      style Cloud fill:#4299e1
  """,
  "Compares edge inference (on-device/gateway) versus cloud inference for ML model serving.",
  """
  - **Edge**: <100ms latency, smaller models, higher infra cost
  - **Cloud**: 200-500ms latency, larger models, economies of scale
  - Use edge for real-time decisions (fraud detection, routing)
  - Use cloud for batch processing or when model size matters
  """,
  :public
)

create_diagram.(
  "Model Lifecycle Management",
  ["mlops", "lifecycle", "deployment", "ml"],
  """
  flowchart TD
      D[Data Collection] --> T[Training]
      T --> V[Validation]
      V --> R{Metrics OK?}
      R -->|No| T
      R -->|Yes| Deploy[Deploy to Staging]
      Deploy --> AB[A/B Test]
      AB --> Prod[Production Rollout]
      Prod --> M[Monitor Metrics]
      M --> |Drift Detected| D
      style M fill:#ed8936
  """,
  "End-to-end ML model lifecycle from training through deployment and monitoring for drift.",
  """
  - Models degrade over time as data distributions shift
  - Monitor prediction accuracy, latency, and feature drift
  - Retrain periodically or when metrics degrade
  - Use A/B testing before full production rollout
  """,
  :public
)

create_diagram.(
  "Feature Store Architecture",
  ["features", "ml", "data"],
  """
  flowchart LR
      subgraph Online
      A[API Request] --> O[Online Store<br/>Redis/DynamoDB]
      O --> I[Inference]
      end
      subgraph Offline
      B[Batch Jobs] --> OF[Offline Store<br/>S3/BigQuery]
      OF --> T[Training]
      end
      D[Data Pipeline] --> O
      D --> OF
      style O fill:#48bb78
      style OF fill:#4299e1
  """,
  "Feature store separates online (low-latency) and offline (batch) feature serving for ML.",
  """
  - **Online Store**: Fast lookup for real-time inference (Redis, DynamoDB)
  - **Offline Store**: Historical features for training (S3, BigQuery)
  - Ensures training/serving consistency
  - Reduces feature engineering duplication across teams
  """,
  :unlisted
)

# Database Optimization diagrams
create_diagram.(
  "PostgreSQL Index Types",
  ["indexing", "performance", "database", "postgres"],
  """
  flowchart TD
      Q[Query] --> I{Index Type}
      I -->|BTREE| B[Equality & Range<br/>WHERE id = 5<br/>WHERE age > 18]
      I -->|HASH| H[Equality Only<br/>WHERE email = 'x@y.com']
      I -->|GIN| G[Full-text Search<br/>Array Containment<br/>JSONB queries]
      I -->|GIST| GI[Geometric Data<br/>Full-text Search<br/>Range Types]
      style I fill:#d69e2e
  """,
  "Compares PostgreSQL index types and their ideal use cases for query optimization.",
  """
  - **BTREE**: Default, best for equality and range queries
  - **HASH**: Faster equality checks, no range support
  - **GIN**: JSONB, arrays, full-text search
  - **GIST**: Geometric data, IP ranges, full-text
  """,
  :public
)

create_diagram.(
  "Query Optimization with EXPLAIN",
  ["explain", "query-planning", "optimization", "postgres"],
  """
  flowchart TD
      Q[Slow Query] --> E[EXPLAIN ANALYZE]
      E --> R{Findings}
      R --> S1[Sequential Scan]
      R --> S2[Hash Join Cost High]
      R --> S3[Sort Operation Expensive]
      S1 --> F1[Add Index]
      S2 --> F2[Increase work_mem]
      S3 --> F3[Add ORDER BY index]
      F1 --> T[Test Again]
      F2 --> T
      F3 --> T
      style E fill:#d69e2e
  """,
  "Workflow for diagnosing and fixing slow queries using PostgreSQL's EXPLAIN ANALYZE.",
  """
  - `EXPLAIN` shows query plan without execution
  - `EXPLAIN ANALYZE` runs query and shows actual times
  - Look for Seq Scans on large tables (add index)
  - Check join costs (consider statistics update or index)
  """,
  :public
)

create_diagram.(
  "Table Partitioning Strategy",
  ["partitioning", "scaling", "performance", "postgres"],
  """
  flowchart TD
      T[Large Table: events<br/>100M+ rows] --> P[Partition by Date]
      P --> P1[events_2024_01]
      P --> P2[events_2024_02]
      P --> P3[events_2024_03]
      Q[Query: WHERE date = '2024-02'<br/>AND user_id = 123] --> PP[Partition Pruning]
      PP --> P2
      style PP fill:#48bb78
  """,
  "Shows how table partitioning improves query performance by pruning irrelevant partitions.",
  """
  - Partition large tables by time, geography, or category
  - Queries with partition key only scan relevant partitions
  - Easier maintenance (drop old partitions vs DELETE)
  - Partitioning by month/week common for time-series data
  """,
  :unlisted
)

# Infrastructure diagrams
create_diagram.(
  "Observability Pipeline",
  ["observability", "monitoring", "logs", "infrastructure"],
  """
  flowchart LR
      A[Application] --> L[Logs]
      A --> M[Metrics]
      A --> T[Traces]
      L --> F[Fluentd/Logstash]
      M --> P[Prometheus]
      T --> J[Jaeger]
      F --> E[Elasticsearch]
      P --> G[Grafana]
      J --> G
      E --> G
      style G fill:#d69e2e
  """,
  "Standard observability stack collecting logs, metrics, and traces into unified dashboards.",
  """
  - **Logs**: Structured events (Fluentd → Elasticsearch)
  - **Metrics**: Time-series data (Prometheus → Grafana)
  - **Traces**: Request flows (Jaeger → Grafana)
  - Correlate using trace IDs across all three
  """,
  :public
)

create_diagram.(
  "Autoscaling Based on Metrics",
  ["autoscaling", "kubernetes", "scaling", "infrastructure"],
  """
  flowchart TD
      M[Metrics: CPU, Latency, Queue Depth] --> HPA[Horizontal Pod Autoscaler]
      HPA --> D{Current vs Target}
      D -->|Above Target| U[Scale Up Pods]
      D -->|Below Target| Down[Scale Down Pods]
      D -->|Within Range| N[No Action]
      U --> W[Wait for Cooldown]
      Down --> W
      style HPA fill:#4299e1
  """,
  "Kubernetes HPA automatically adjusts pod count based on observed metrics like CPU or custom metrics.",
  """
  - Monitor CPU, memory, or custom metrics (e.g., queue length)
  - Scale up when metrics exceed target for sustained period
  - Scale down when metrics below target (with longer cooldown)
  - Set min/max pod limits to control costs
  """,
  :public
)

create_diagram.(
  "Multi-Layer Fallback Architecture",
  ["resilience", "fallback", "architecture", "infrastructure"],
  """
  flowchart TD
      R[Request] --> L1{Local Cache}
      L1 -->|Hit| R1[Return Cached]
      L1 -->|Miss| L2{Edge Service}
      L2 -->|Available| R2[Return from Edge]
      L2 -->|Down| L3{Cloud Service}
      L3 -->|Available| R3[Return from Cloud]
      L3 -->|Down| F[Static Fallback/Error]
      style L1 fill:#48bb78
      style L2 fill:#ed8936
      style L3 fill:#e53e3e
  """,
  "Cascading fallback strategy across multiple service tiers for high availability.",
  """
  - Layer 1: Local cache (fastest, most reliable)
  - Layer 2: Edge service (fast, regional)
  - Layer 3: Cloud service (slower, centralized)
  - Layer 4: Static fallback (degraded experience)
  """,
  :unlisted
)

create_diagram.(
  "Rate Limiting with Token Bucket",
  ["rate-limiting", "api", "throttling", "infrastructure"],
  """
  flowchart TD
      R[Request] --> B{Bucket Has Tokens?}
      B -->|Yes| C[Consume Token]
      C --> P[Process Request]
      B -->|No| Reject[Reject with 429]
      T[Token Refill:<br/>+X tokens per second] --> Bu[Bucket]
      Bu --> B
      style B fill:#d69e2e
      style Reject fill:#e53e3e
  """,
  "Token bucket algorithm for rate limiting API requests, allowing bursts while enforcing average rate.",
  """
  - Bucket starts with N tokens
  - Each request consumes 1 token
  - Tokens refill at steady rate (e.g., 10/sec)
  - Allows bursts up to bucket capacity
  """,
  :public
)

IO.puts("Diagrams created successfully!")

# Print summary
total_diagrams = Repo.aggregate(Diagram, :count, :id)
public_count = Repo.aggregate(from(d in Diagram, where: d.visibility == :public), :count, :id)
unlisted_count = Repo.aggregate(from(d in Diagram, where: d.visibility == :unlisted), :count, :id)

IO.puts("✓ Created #{total_diagrams} diagrams (#{public_count} public, #{unlisted_count} unlisted)")
IO.puts("✓ All diagrams owned by seed user: #{seed_user.email}")

# Group by tag and show counts
tag_counts =
  Repo.all(Diagram)
  |> Enum.flat_map(& &1.tags)
  |> Enum.frequencies()
  |> Enum.sort_by(fn {_tag, count} -> -count end)
  |> Enum.take(10)

IO.puts("\nTop tags:")

Enum.each(tag_counts, fn {tag, count} ->
  IO.puts("  - #{tag}: #{count} diagrams")
end)
