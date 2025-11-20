defmodule PromExPlugin.OsMetrics do
  @moduledoc """
  Shared PromEx plugin for OS-level metrics via :os_mon.

  This plugin is service-agnostic and uses standardized metric names.
  The `job` label (added by Prometheus scrape config) identifies which service.

  Exposes Prometheus metrics for:
  - CPU load averages (1min, 5min, 15min)
  - CPU utilization percentage
  - System memory usage
  - Disk usage

  ## Usage

  Add to your service's PromEx module:

      def plugins do
        [
          PromExPlugin.OsMetrics
        ]
      end

  ## Metrics Exposed

  All metrics use standardized names (no app prefix):

  - `prom_ex_os_mon_cpu_avg1` - 1-minute load average
  - `prom_ex_os_mon_cpu_avg5` - 5-minute load average
  - `prom_ex_os_mon_cpu_avg15` - 15-minute load average
  - `prom_ex_os_mon_cpu_util` - CPU utilization (0-100%)
  - `prom_ex_os_mon_memory_total` - Total system memory (bytes)
  - `prom_ex_os_mon_memory_allocated` - Allocated memory (bytes)
  - `prom_ex_os_mon_system_memory_available_memory` - Available memory (bytes)
  - `prom_ex_os_mon_system_memory_free_memory` - Free memory (bytes)

  ## Querying in Grafana

  ```promql
  # CPU utilization for all services
  prom_ex_os_mon_cpu_util

  # CPU for specific service
  prom_ex_os_mon_cpu_util{job="image_svc"}

  # Average CPU across all services
  avg(prom_ex_os_mon_cpu_util)

  # CPU by service (grouped)
  sum by (job) (prom_ex_os_mon_cpu_util)
  ```
  """
  use PromEx.Plugin
  require Logger

  @impl true
  def polling_metrics(opts) do
    Logger.info("[PromExPlugin.OsMetrics] Starting OS metrics polling")
    poll_rate = Keyword.get(opts, :poll_rate, 5_000)

    [
      os_metrics(poll_rate)
    ]
  end

  @doc """
  Build polling metric struct with standardized metric names.

  Note: We don't use the app name in metric names to allow querying across services.
  The Prometheus `job` label identifies which service the metric comes from.
  """
  def os_metrics(poll_rate) do
    Polling.build(
      :prom_ex_os_metrics_polling,
      poll_rate,
      {__MODULE__, :execute_os_metrics, []},
      [
        # CPU load averages (scaled by 256 by :cpu_sup)
        last_value(
          [:prom_ex, :os_mon, :cpu, :avg1],
          event_name: [:prom_ex, :plugin, :os_mon],
          description: "System load average over 1 minute (scaled by 256)",
          measurement: &get_in(&1, [:cpu, :avg1])
        ),
        last_value(
          [:prom_ex, :os_mon, :cpu, :avg5],
          event_name: [:prom_ex, :plugin, :os_mon],
          description: "System load average over 5 minutes (scaled by 256)",
          measurement: &get_in(&1, [:cpu, :avg5])
        ),
        last_value(
          [:prom_ex, :os_mon, :cpu, :avg15],
          event_name: [:prom_ex, :plugin, :os_mon],
          description: "System load average over 15 minutes (scaled by 256)",
          measurement: &get_in(&1, [:cpu, :avg15])
        ),

        # CPU utilization percentage
        last_value(
          [:prom_ex, :os_mon, :cpu, :util],
          event_name: [:prom_ex, :plugin, :os_mon],
          unit: :percent,
          description: "CPU utilization percentage (0-100)",
          measurement: &get_in(&1, [:cpu, :util])
        ),

        # Memory metrics from get_memory_data
        last_value(
          [:prom_ex, :os_mon, :memory, :total],
          event_name: [:prom_ex, :plugin, :os_mon],
          unit: :byte,
          description: "Total system memory in bytes",
          measurement: &get_in(&1, [:memory, :total])
        ),
        last_value(
          [:prom_ex, :os_mon, :memory, :allocated],
          event_name: [:prom_ex, :plugin, :os_mon],
          unit: :byte,
          description: "Allocated memory in bytes",
          measurement: &get_in(&1, [:memory, :allocated])
        ),

        # System memory from get_system_memory_data
        last_value(
          [:prom_ex, :os_mon, :system_memory, :available_memory],
          event_name: [:prom_ex, :plugin, :os_mon],
          unit: :byte,
          description: "Available system memory in bytes",
          measurement: &get_in(&1, [:system_memory, :available_memory])
        ),
        last_value(
          [:prom_ex, :os_mon, :system_memory, :free_memory],
          event_name: [:prom_ex, :plugin, :os_mon],
          unit: :byte,
          description: "Free system memory in bytes",
          measurement: &get_in(&1, [:system_memory, :free_memory])
        )
      ]
    )
  end

  @doc """
  Collects OS metrics from :os_mon applications.
  Called periodically by PromEx polling mechanism.
  """
  def execute_os_metrics do
    # CPU metrics
    cpu_metrics = %{
      avg1: :cpu_sup.avg1(),
      avg5: :cpu_sup.avg5(),
      avg15: :cpu_sup.avg15(),
      util: :cpu_sup.util()
    }

    # Memory metrics - handle both 3-tuple and 4-tuple format
    memory_metrics =
      case :memsup.get_memory_data() do
        {total, allocated, {_worst_pid, _worst_mem}} ->
          # Alpine Linux / 3-tuple format
          %{total: total, allocated: allocated}

        {total, allocated, :undefined} ->
          # Standard 4-tuple format
          %{total: total, allocated: allocated}
      end

    # System memory (returns keyword list)
    system_memory_data = :memsup.get_system_memory_data()

    system_memory_metrics = %{
      available_memory: Keyword.get(system_memory_data, :available_memory, 0),
      free_memory: Keyword.get(system_memory_data, :free_memory, 0)
    }

    os_measures = %{
      cpu: cpu_metrics,
      memory: memory_metrics,
      system_memory: system_memory_metrics
    }

    :telemetry.execute([:prom_ex, :plugin, :os_mon], os_measures, %{})
  end
end
