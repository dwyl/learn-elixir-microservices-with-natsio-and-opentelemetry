defmodule EventStore do
  @moduledoc """
  Simple ETS-based event store for tracking message processing.

  Provides event sourcing capabilities:
  - Unique event tracking by job_id
  - Sequential event ordering per aggregate/action_type
  - Fast idempotency checks
  - Event replay capability

  ## Architecture

  Two ETS tables:
  1. `:events` - Main event log (set, unique by job_id)
  2. `:event_counters` - Sequential counters per {aggregate, action_type}

  ## Event Structure

      %{
        job_id: "uuid-123",           # Unique event identifier
        aggregate: :email,             # Aggregate type: :email, :image
        action_type: :welcome,         # Action: :welcome, :notification, :bin_to_pdf, :url_to_pdf
        event_order_id: 42,            # Sequential ID for this aggregate+action
        timestamp: ~U[2025-03-22 10:00:00Z],
        metadata: %{...}               # Optional additional data
      }

  ## Usage

      # Start the event store (in application.ex)
      EventStore.start_link()

      # Try to register a new event (idempotent)
      case EventStore.register_event("job_123", :email, :welcome) do
        {:ok, event} ->
          # Event registered, proceed with processing
          send_email(...)

        {:error, :already_exists, existing_event} ->
          # Event already processed, skip
          Logger.info("Event already processed at #{existing_event.timestamp}")
      end

      # Check if event exists
      EventStore.exists?("job_123")  # => true

      # Get event details
      EventStore.get_event("job_123")  # => %{job_id: "job_123", ...}

      # Get all events for an aggregate+action (in order)
      EventStore.get_events_by_type(:email, :welcome)  # => [%{event_order_id: 1, ...}, ...]

  ## Benefits

  - **Idempotency**: Prevents duplicate processing via unique job_id
  - **Audit trail**: Complete event log with timestamps
  - **Sequential ordering**: Track event order per aggregate/action
  - **Fast lookups**: O(1) ETS lookups for existence checks
  - **In-memory**: No database required (can persist to disk if needed)

  ## Event Sourcing Pattern

  This implements a simplified event sourcing pattern where:
  - Each event is immutable (write-once)
  - Events are ordered sequentially
  - System state can be rebuilt by replaying events
  - Idempotency is guaranteed by unique job_id

  ## Trade-offs

  ✅ Pros:
  - Fast (in-memory ETS)
  - Simple (no external dependencies)
  - Idempotent (guaranteed no duplicates)
  - Audit trail (all events tracked)

  ⚠️ Cons:
  - In-memory only (lost on restart unless persisted)
  - Single-node (not distributed across multiple servers)
  - No automatic cleanup (events accumulate)

  For production, consider:
  - Periodic persistence to disk (`:ets.tab2file/2`)
  - Event archival/cleanup (remove old events)
  - Distributed event store (Postgres, EventStoreDB, etc.)
  """

  use GenServer
  require Logger

  @events_table :events
  @counters_table :event_counters

  ## Client API

  @doc """
  Start the EventStore GenServer and initialize ETS tables.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Register a new event. Returns {:ok, event} if new, {:error, :already_exists, event} if duplicate.

  ## Examples

      iex> EventStore.register_event("job_123", :email, :welcome)
      {:ok, %{job_id: "job_123", aggregate: :email, action_type: :welcome, event_order_id: 1, ...}}

      iex> EventStore.register_event("job_123", :email, :welcome)  # Duplicate
      {:error, :already_exists, %{job_id: "job_123", ...}}

  """
  def register_event(job_id, aggregate, action_type, metadata \\ %{}) do
    GenServer.call(__MODULE__, {:register_event, job_id, aggregate, action_type, metadata})
  end

  @doc """
  Check if an event exists by job_id.

  ## Examples

      iex> EventStore.exists?("job_123")
      true

      iex> EventStore.exists?("unknown")
      false

  """
  def exists?(job_id) do
    case :ets.lookup(@events_table, job_id) do
      [{^job_id, _event}] -> true
      [] -> false
    end
  end

  @doc """
  Get event details by job_id.

  ## Examples

      iex> EventStore.get_event("job_123")
      %{job_id: "job_123", aggregate: :email, action_type: :welcome, ...}

      iex> EventStore.get_event("unknown")
      nil

  """
  def get_event(job_id) do
    case :ets.lookup(@events_table, job_id) do
      [{^job_id, event}] -> event
      [] -> nil
    end
  end

  @doc """
  Get all events for a specific aggregate and action type, ordered by event_order_id.

  ## Examples

      iex> EventStore.get_events_by_type(:email, :welcome)
      [
        %{job_id: "job_1", event_order_id: 1, ...},
        %{job_id: "job_2", event_order_id: 2, ...}
      ]

  """
  def get_events_by_type(aggregate, action_type) do
    :ets.match_object(@events_table, {:_, %{aggregate: aggregate, action_type: action_type}})
    |> Enum.map(fn {_job_id, event} -> event end)
    |> Enum.sort_by(& &1.event_order_id)
  end

  @doc """
  Get all events (for debugging/replay).

  ## Examples

      iex> EventStore.get_all_events()
      [%{job_id: "job_1", ...}, %{job_id: "job_2", ...}]

  """
  def get_all_events do
    :ets.tab2list(@events_table)
    |> Enum.map(fn {_job_id, event} -> event end)
    |> Enum.sort_by(& &1.timestamp, DateTime)
  end

  @doc """
  Get current counter value for an aggregate+action type.

  ## Examples

      iex> EventStore.get_counter(:email, :welcome)
      42

  """
  def get_counter(aggregate, action_type) do
    key = {aggregate, action_type}

    case :ets.lookup(@counters_table, key) do
      [{^key, count}] -> count
      [] -> 0
    end
  end

  @doc """
  Get statistics about the event store.

  ## Examples

      iex> EventStore.stats()
      %{
        total_events: 100,
        events_by_aggregate: %{email: 60, image: 40},
        events_by_type: %{{:email, :welcome} => 30, {:email, :notification} => 30, ...}
      }

  """
  def stats do
    events = get_all_events()

    %{
      total_events: length(events),
      events_by_aggregate:
        events
        |> Enum.group_by(& &1.aggregate)
        |> Map.new(fn {agg, evts} -> {agg, length(evts)} end),
      events_by_type:
        events
        |> Enum.group_by(&{&1.aggregate, &1.action_type})
        |> Map.new(fn {key, evts} -> {key, length(evts)} end)
    }
  end

  @doc """
  Clear all events (for testing only).
  """
  def clear_all do
    GenServer.call(__MODULE__, :clear_all)
  end

  ## Server Callbacks

  @impl true
  def init(_opts) do
    # Create ETS tables
    events_table = :ets.new(@events_table, [:set, :public, :named_table, read_concurrency: true])

    counters_table =
      :ets.new(@counters_table, [:set, :public, :named_table, read_concurrency: true])

    Logger.info("[EventStore] Initialized with tables: #{inspect(@events_table)}, #{inspect(@counters_table)}")

    {:ok, %{events_table: events_table, counters_table: counters_table}}
  end

  @impl true
  def handle_call({:register_event, job_id, aggregate, action_type, metadata}, _from, state) do
    # Check if event already exists
    case :ets.lookup(@events_table, job_id) do
      [{^job_id, existing_event}] ->
        Logger.debug("[EventStore] Event already exists: #{job_id}")
        {:reply, {:error, :already_exists, existing_event}, state}

      [] ->
        # Increment counter for this aggregate+action type
        counter_key = {aggregate, action_type}
        event_order_id = :ets.update_counter(@counters_table, counter_key, {2, 1}, {counter_key, 0})

        # Create event
        event = %{
          job_id: job_id,
          aggregate: aggregate,
          action_type: action_type,
          event_order_id: event_order_id,
          timestamp: DateTime.utc_now(),
          metadata: metadata
        }

        # Insert event
        true = :ets.insert(@events_table, {job_id, event})

        Logger.debug(
          "[EventStore] Registered event: #{job_id} (#{aggregate}:#{action_type} ##{event_order_id})"
        )

        {:reply, {:ok, event}, state}
    end
  end

  @impl true
  def handle_call(:clear_all, _from, state) do
    :ets.delete_all_objects(@events_table)
    :ets.delete_all_objects(@counters_table)
    Logger.info("[EventStore] Cleared all events")
    {:reply, :ok, state}
  end
end
