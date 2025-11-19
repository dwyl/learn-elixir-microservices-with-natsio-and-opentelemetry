defmodule PromExPlugin.OsMetrics do
  @moduledoc """
  Custom PromEx plugin for OS-level metrics via :os_mon.

  Exposes Prometheus metrics for:
  - CPU load averages (1min, 5min, 15min)
  - CPU utilization percentage
  - System memory usage
  - Disk usage

  Source: <https://hexdocs.pm/prom_ex/writing-promex-plugins.html#adding-polling-metrics

  """
  use PromEx.Plugin
  require Logger

  @impl true
  def polling_metrics(opts) do
    Logger.info("OS Metrics Polling metrics started")
    poll_rate = Keyword.get(opts, :poll_rate, 5_000)

    [
      os_metrics(poll_rate)
    ]
  end

  @doc """
  We use build/3 to builld the struct that defines our polling metric sruct.

  Source: <https://hexdocs.pm/prom_ex/PromEx.MetricTypes.Polling.html>

  We execute __MODULE__.execute_os_metrics() every `poll_rate` milliseconds to collect
  OS metrics via :os_mon and expose them as Prometheus metrics.
  """

  def os_metrics(poll_rate) do
    Polling.build(
      :email_svc_prom_ex_os_metrics,
      poll_rate,
      {__MODULE__, :execute_os_metrics, []},
      [
        # CPU load averages
        last_value(
          [:email_svc, :prom_ex, :os_mon, :cpu, :avg1],
          event_name: [:prom_ex, :plugin, :os_mon],
          description: "System load average over 1 minute (scaled by 256)",
          measurement: &get_in(&1, [:cpu, :avg1])
        ),
        last_value(
          [:email_svc, :prom_ex, :os_mon, :cpu, :avg5],
          event_name: [:prom_ex, :plugin, :os_mon],
          description: "System load average over 5 minutes (scaled by 256)",
          measurement: &get_in(&1, [:cpu, :avg5])
        ),
        last_value(
          [:email_svc, :prom_ex, :os_mon, :cpu, :avg15],
          event_name: [:prom_ex, :plugin, :os_mon],
          description: "System load average over 15 minutes (scaled by 256)",
          measurement: &get_in(&1, [:cpu, :avg15])
        ),

        # CPU utilization
        last_value(
          [:email_svc, :prom_ex, :os_mon, :cpu, :util],
          event_name: [:prom_ex, :plugin, :os_mon],
          unit: :percent,
          description: "CPU utilization percentage (0-100)",
          measurement: &get_in(&1, [:cpu, :util])
        ),

        # Memory metrics
        last_value(
          [:email_svc, :prom_ex, :os_mon, :memory, :total],
          event_name: [:prom_ex, :plugin, :os_mon],
          unit: :byte,
          description: "Total system memory in bytes",
          measurement: &get_in(&1, [:memory, :total])
        ),
        last_value(
          [:email_svc, :prom_ex, :os_mon, :memory, :allocated],
          event_name: [:prom_ex, :plugin, :os_mon],
          unit: :byte,
          description: "Allocated memory in bytes",
          measurement: &get_in(&1, [:memory, :allocated])
        ),

        # System memory (from get_system_memory_data)
        last_value(
          [:email_svc, :prom_ex, :os_mon, :system_memory, :available_memory],
          event_name: [:prom_ex, :plugin, :os_mon],
          unit: :byte,
          description: "Available system memory in bytes",
          measurement: &get_in(&1, [:system_memory, :available_memory])
        ),
        last_value(
          [:email_svc, :prom_ex, :os_mon, :system_memory, :free_memory],
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
