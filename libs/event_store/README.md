# EventStore - ETS-based Event Sourcing

A simple, fast event store using ETS for tracking message processing in microservices.

## Features

- **Idempotency** - Prevents duplicate event processing via unique `job_id`
- **Event ordering** - Sequential `event_order_id` per `{aggregate, action_type}`
- **Fast lookups** - O(1) ETS lookups for existence checks
- **Audit trail** - Complete event log with timestamps
- **In-memory** - No database required (optional disk persistence)

## Architecture

### Two ETS Tables

1. **`:events`** (set, unique by job_id)
   - Key: `job_id`
   - Value: Event struct with metadata

2. **`:event_counters`** (set, unique by {aggregate, action_type})
   - Key: `{aggregate, action_type}`
   - Value: Counter (integer)

### Event Structure

```elixir
%{
  job_id: "uuid-123",              # Unique event identifier
  aggregate: :email,                # :email, :image, :user
  action_type: :welcome,            # :welcome, :notification, :bin_to_pdf, :url_to_pdf
  event_order_id: 42,               # Sequential ID for this aggregate+action
  timestamp: ~U[2025-03-22 10:00:00Z],
  metadata: %{                      # Optional additional data
    user_id: "user_123",
    user_email: "user@example.com"
  }
}
```

## Usage

### 1. Start EventStore (in application.ex)

```elixir
# apps/user_svc/lib/user_svc/application.ex
def start(_type, _args) do
  children = [
    # ... other children
    EventStore,  # Add this
  ]

  opts = [strategy: :one_for_one, name: UserService.Supervisor]
  Supervisor.start_link(children, opts)
end
```

### 2. Add Dependency (in mix.exs)

```elixir
# apps/user_svc/mix.exs
defp deps do
  [
    {:event_store, path: "../../libs/event_store"},
    # ... other deps
  ]
end
```

### 3. Use in Message Handler

```elixir
defmodule UserService.NatsConsumer do
  def handle_message(%{topic: "user.email.create", body: body} = message) do
    req = Mcsv.V3.UserRequest.decode(body)

    # Check if event already processed (idempotency)
    case EventStore.register_event(req.job_id, :email, req.type) do
      {:ok, event} ->
        # New event, proceed with processing
        Logger.info("[NatsConsumer] Processing new event: #{req.job_id} (event ##{event.event_order_id})")
        forward_to_email_service(req)

      {:error, :already_exists, existing_event} ->
        # Duplicate event, skip processing
        Logger.warn(
          "[NatsConsumer] Duplicate event detected: #{req.job_id} " <>
          "(already processed at #{existing_event.timestamp})"
        )
        :ok  # Acknowledge message but don't process
    end
  end

  defp forward_to_email_service(req) do
    trace_headers = OtelNats.inject()
    headers_with_msg_id = [{"Nats-Msg-Id", req.job_id} | trace_headers]

    case req.type do
      :EMAIL_TYPE_WELCOME ->
        :ok = Gnat.pub(:gnat, "email.welcome", body, headers: headers_with_msg_id)
      :EMAIL_TYPE_NOTIFICATION ->
        :ok = Gnat.pub(:gnat, "email.notification", body, headers: headers_with_msg_id)
    end
  end
end
```

## API Examples

### Register Event (Idempotent)

```elixir
# First call - registers event
EventStore.register_event("job_123", :email, :welcome, %{user_id: "user_1"})
# => {:ok, %{job_id: "job_123", event_order_id: 1, timestamp: ~U[...], ...}}

# Second call - returns existing event
EventStore.register_event("job_123", :email, :welcome)
# => {:error, :already_exists, %{job_id: "job_123", ...}}
```

### Check Event Existence

```elixir
EventStore.exists?("job_123")
# => true

EventStore.exists?("unknown")
# => false
```

### Get Event Details

```elixir
EventStore.get_event("job_123")
# => %{job_id: "job_123", aggregate: :email, action_type: :welcome, event_order_id: 1, ...}
```

### Get Events by Type (Ordered)

```elixir
EventStore.get_events_by_type(:email, :welcome)
# => [
#      %{job_id: "job_1", event_order_id: 1, timestamp: ~U[2025-03-22 10:00:00Z]},
#      %{job_id: "job_2", event_order_id: 2, timestamp: ~U[2025-03-22 10:01:00Z]},
#      %{job_id: "job_3", event_order_id: 3, timestamp: ~U[2025-03-22 10:02:00Z]}
#    ]
```

### Get Statistics

```elixir
EventStore.stats()
# => %{
#      total_events: 100,
#      events_by_aggregate: %{email: 60, image: 40},
#      events_by_type: %{
#        {:email, :welcome} => 30,
#        {:email, :notification} => 30,
#        {:image, :bin_to_pdf} => 20,
#        {:image, :url_to_pdf} => 20
#      }
#    }
```

### Get Counter Value

```elixir
EventStore.get_counter(:email, :welcome)
# => 30  # 30 welcome emails processed
```

## Event Types by Aggregate

### Email Aggregate

- `:welcome` - Welcome email to new users
- `:notification` - General notification emails

### Image Aggregate

- `:bin_to_pdf` - Binary image to PDF conversion
- `:url_to_pdf` - S3 image to PDF conversion

## Benefits Over NATS Deduplication Alone

| Feature              | NATS JetStream Dedup | EventStore | Combined       |
| -------------------- | -------------------- | ---------- | -------------- |
| Deduplication window | 2 minutes            | Forever*   | ✅ Best of both |
| Audit trail          | ❌ No                 | ✅ Yes      | ✅ Yes          |
| Event ordering       | ❌ No                 | ✅ Yes      | ✅ Yes          |
| Event replay         | ❌ No                 | ✅ Yes      | ✅ Yes          |
| Cross-service        | ❌ Per stream         | ✅ Global   | ✅ Global       |

*EventStore keeps events indefinitely (until cleared or archived)

## Recommended Strategy: Defense in Depth

Use **both** NATS deduplication and EventStore:

```elixir
# 1. NATS deduplication (network-level, 2-minute window)
headers_with_msg_id = [{"Nats-Msg-Id", req.job_id} | trace_headers]
:ok = Gnat.pub(:gnat, "email.welcome", body, headers: headers_with_msg_id)

# 2. EventStore deduplication (application-level, permanent)
case EventStore.register_event(req.job_id, :email, :welcome) do
  {:ok, _event} -> process_email(req)
  {:error, :already_exists, _event} -> :skip
end
```

**Why both?**

- **NATS dedup**: Fast, prevents network-level duplicates
- **EventStore**: Permanent audit trail, survives restarts, enables event sourcing

## Persistence (Optional)

### Save to Disk

```elixir
# Periodically save events to disk
:ets.tab2file(:events, '/tmp/events_backup.ets')
:ets.tab2file(:event_counters, '/tmp/counters_backup.ets')
```

### Load from Disk

```elixir
# On startup, restore from backup
{:ok, _table} = :ets.file2tab('/tmp/events_backup.ets')
{:ok, _table} = :ets.file2tab('/tmp/counters_backup.ets')
```

### Scheduled Backups (in application.ex)

```elixir
def start(_type, _args) do
  children = [
    EventStore,
    {Task, fn -> schedule_backups() end}
  ]

  # ...
end

defp schedule_backups do
  # Backup every hour
  :timer.apply_interval(3_600_000, :ets, :tab2file, [:events, '/data/events_backup.ets'])
  :timer.apply_interval(3_600_000, :ets, :tab2file, [:event_counters, '/data/counters_backup.ets'])
end
```

## Event Cleanup (Production)

For production, implement periodic cleanup:

```elixir
defmodule EventStore.Cleaner do
  use GenServer

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    # Clean old events every hour
    schedule_cleanup()
    {:ok, %{}}
  end

  @impl true
  def handle_info(:cleanup, state) do
    # Delete events older than 7 days
    cutoff = DateTime.add(DateTime.utc_now(), -7, :day)

    EventStore.get_all_events()
    |> Enum.filter(&(DateTime.compare(&1.timestamp, cutoff) == :lt))
    |> Enum.each(fn event ->
      :ets.delete(:events, event.job_id)
    end)

    schedule_cleanup()
    {:noreply, state}
  end

  defp schedule_cleanup do
    # Run every hour
    Process.send_after(self(), :cleanup, :timer.hours(1))
  end
end
```

## Testing

```elixir
defmodule EventStoreTest do
  use ExUnit.Case

  setup do
    EventStore.clear_all()
    :ok
  end

  test "registers new event" do
    assert {:ok, event} = EventStore.register_event("job_1", :email, :welcome)
    assert event.job_id == "job_1"
    assert event.aggregate == :email
    assert event.action_type == :welcome
    assert event.event_order_id == 1
  end

  test "detects duplicate events" do
    {:ok, _} = EventStore.register_event("job_1", :email, :welcome)

    assert {:error, :already_exists, existing} =
             EventStore.register_event("job_1", :email, :welcome)

    assert existing.job_id == "job_1"
  end

  test "increments event order per aggregate+action" do
    {:ok, e1} = EventStore.register_event("job_1", :email, :welcome)
    {:ok, e2} = EventStore.register_event("job_2", :email, :welcome)
    {:ok, e3} = EventStore.register_event("job_3", :email, :welcome)

    assert e1.event_order_id == 1
    assert e2.event_order_id == 2
    assert e3.event_order_id == 3
  end

  test "separate counters for different types" do
    {:ok, e1} = EventStore.register_event("job_1", :email, :welcome)
    {:ok, e2} = EventStore.register_event("job_2", :email, :notification)
    {:ok, e3} = EventStore.register_event("job_3", :image, :bin_to_pdf)

    assert e1.event_order_id == 1  # email:welcome counter
    assert e2.event_order_id == 1  # email:notification counter
    assert e3.event_order_id == 1  # image:bin_to_pdf counter
  end
end
```

## Migration Guide

### Before (NATS dedup only)

```elixir
def handle_message(%{topic: "user.email.create", body: body}) do
  req = Mcsv.V3.UserRequest.decode(body)

  # Only NATS dedup (2-minute window)
  headers = [{"Nats-Msg-Id", req.job_id}]
  :ok = Gnat.pub(:gnat, "email.welcome", body, headers: headers)
end
```

### After (NATS + EventStore)

```elixir
def handle_message(%{topic: "user.email.create", body: body}) do
  req = Mcsv.V3.UserRequest.decode(body)

  # Application-level dedup (permanent)
  case EventStore.register_event(req.job_id, :email, :welcome) do
    {:ok, event} ->
      Logger.info("Processing event ##{event.event_order_id}")

      # Network-level dedup (2-minute window)
      headers = [{"Nats-Msg-Id", req.job_id}]
      :ok = Gnat.pub(:gnat, "email.welcome", body, headers: headers)

    {:error, :already_exists, event} ->
      Logger.warn("Skipping duplicate event (processed at #{event.timestamp})")
      :ok
  end
end
```

## Next Steps

1. Add EventStore to user_svc application.ex
2. Update NatsConsumer to use EventStore.register_event()
3. Add monitoring dashboard showing event statistics
4. Implement periodic backups to disk
5. Add event cleanup for old events

## References

- [Event Sourcing Pattern](https://martinfowler.com/eaaDev/EventSourcing.html)
- [ETS Documentation](https://www.erlang.org/doc/man/ets.html)
- [Idempotency in Distributed Systems](https://aws.amazon.com/builders-library/making-retries-safe-with-idempotent-APIs/)
