# Supervision Tree Improvements

## Overview

Analysis of DiagramForge's OTP supervision architecture identified two issues that need addressing to improve fault tolerance and observability.

**Overall Assessment**: Good crash isolation - user sessions are well-isolated and component failures don't cascade.

## Current Architecture

```
DiagramForge.Supervisor [:one_for_one]
├── DiagramForgeWeb.Telemetry (supervisor)
├── DiagramForge.Repo (Ecto connection pool)
├── DiagramForge.Vault (Cloak encryption)
├── Oban (background job processor)
├── DNSCluster
├── Phoenix.PubSub
└── DiagramForgeWeb.Endpoint (Phoenix + LiveView)
```

## Issues to Address

### Issue 1: Unsupervised Task in Usage Tracking (HIGH)

**Location**: `lib/diagram_forge/usage/tracker.ex:28`

**Problem**:
```elixir
def track_usage(model_api_name, usage, opts) do
  Task.start(fn ->
    do_track_usage(model_api_name, usage, opts)
  end)
  :ok
end
```

`Task.start/1` creates an unsupervised task. If it crashes:
- No logging of the failure
- No visibility into the error
- Silent data loss for usage tracking

**Impact**: Usage data for API calls may be silently lost without any indication.

**Solution**:

1. Add Task.Supervisor to the supervision tree:

```elixir
# lib/diagram_forge/application.ex
children = [
  DiagramForgeWeb.Telemetry,
  DiagramForge.Repo,
  DiagramForge.Vault,
  {Task.Supervisor, name: DiagramForge.TaskSupervisor},  # ADD THIS
  {Oban, Application.fetch_env!(:diagram_forge, Oban)},
  # ...rest of children
]
```

2. Update the tracker to use supervised tasks:

```elixir
# lib/diagram_forge/usage/tracker.ex
def track_usage(model_api_name, usage, opts) do
  Task.Supervisor.start_child(
    DiagramForge.TaskSupervisor,
    fn -> do_track_usage(model_api_name, usage, opts) end,
    restart: :temporary
  )
  :ok
end
```

**Benefits**:
- Crashes are logged automatically
- Telemetry events for monitoring
- Proper OTP supervision (temporary = don't restart, but log)

---

### Issue 2: ETS Cache Outside Supervision (MEDIUM)

**Location**: `lib/diagram_forge/application.ex`

**Problem**:
```elixir
def start(_type, _args) do
  DiagramForge.AI.start_cache()  # ETS created before supervision tree
  children = [...]
end
```

The ETS cache is created outside the supervision tree, making its lifecycle inconsistent with the application.

**Impact**:
- If supervision tree crashes but Application remains, ETS survives with potentially stale data
- Cache lifecycle not tied to application lifecycle

**Solution**:

1. Create a supervised cache server:

```elixir
# lib/diagram_forge/ai/cache_server.ex
defmodule DiagramForge.AI.CacheServer do
  @moduledoc """
  Supervised GenServer that owns the prompt cache ETS table.
  """
  use GenServer

  @table_name :prompt_cache

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @impl true
  def init(_) do
    table = :ets.new(@table_name, [:named_table, :public, read_concurrency: true])
    {:ok, %{table: table}}
  end

  # Public API delegates to ETS directly for performance
  def get(key) do
    case :ets.lookup(@table_name, key) do
      [{^key, value}] -> {:ok, value}
      [] -> :miss
    end
  end

  def put(key, value) do
    :ets.insert(@table_name, {key, value})
    :ok
  end
end
```

2. Add to supervision tree:

```elixir
# lib/diagram_forge/application.ex
children = [
  DiagramForgeWeb.Telemetry,
  DiagramForge.Repo,
  DiagramForge.Vault,
  {Task.Supervisor, name: DiagramForge.TaskSupervisor},
  DiagramForge.AI.CacheServer,  # ADD THIS
  {Oban, Application.fetch_env!(:diagram_forge, Oban)},
  # ...
]
```

3. Remove the manual cache start:

```elixir
# lib/diagram_forge/application.ex
def start(_type, _args) do
  # REMOVE: DiagramForge.AI.start_cache()
  children = [...]
end
```

4. Update `DiagramForge.AI` module to use the new server (or keep using ETS directly since it's public).

---

## Future Improvements (Lower Priority)

### Circuit Breaker for OpenAI API

Add `:fuse` library for circuit breaking during prolonged API outages.

```elixir
# mix.exs
{:fuse, "~> 2.5"}

# Usage in client
case :fuse.ask(:openai_api, :sync) do
  :ok -> do_chat(messages, opts)
  :blown -> raise "OpenAI API circuit breaker is open"
end
```

**Benefits**: Fast failure during outages, automatic recovery detection, better resource utilization.

### Rate Limiting for Document Uploads

Add `:hammer` library for rate limiting.

```elixir
# mix.exs
{:hammer, "~> 6.2"}

# Usage in LiveView
case Hammer.check_rate("upload:#{user_id}", 60_000, 5) do
  {:allow, _count} -> process_upload(socket)
  {:deny, _limit} -> {:noreply, put_flash(socket, :error, "Rate limit exceeded")}
end
```

**Benefits**: Protects system from abuse, ensures fair resource allocation.

---

## Risk Matrix

| Component | Crash Impact | Isolation | Risk Level |
|-----------|-------------|-----------|------------|
| LiveView session | Single user | Excellent | LOW |
| Oban worker | Single job | Excellent | LOW |
| OpenAI API call | Single request | Good | LOW |
| Database pool | Queue delay | Good | LOW |
| **Usage tracking** | **Data loss** | **None** | **HIGH** |
| **ETS cache** | **State inconsistency** | **Partial** | **MEDIUM** |

---

## Implementation Checklist

- [ ] Add `Task.Supervisor` to application.ex
- [ ] Update `Usage.Tracker` to use `Task.Supervisor.start_child/3`
- [ ] Create `DiagramForge.AI.CacheServer` GenServer
- [ ] Add CacheServer to supervision tree
- [ ] Remove manual `start_cache()` call from application.ex
- [ ] Update any direct ETS calls if needed
- [ ] Add tests for crash isolation scenarios
- [ ] Run full test suite to verify no regressions

---

## Files to Modify

1. `lib/diagram_forge/application.ex` - Add Task.Supervisor and CacheServer
2. `lib/diagram_forge/usage/tracker.ex` - Use Task.Supervisor
3. `lib/diagram_forge/ai/cache_server.ex` - New file for supervised cache
4. `lib/diagram_forge/ai.ex` - Remove `start_cache/0` if present

---

## References

- [Elixir Task.Supervisor docs](https://hexdocs.pm/elixir/Task.Supervisor.html)
- [OTP Supervision principles](https://www.erlang.org/doc/design_principles/sup_princ.html)
- [Fuse circuit breaker](https://github.com/jlouis/fuse)
- [Hammer rate limiting](https://github.com/ExHammer/hammer)
