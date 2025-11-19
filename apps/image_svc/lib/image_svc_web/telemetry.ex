defmodule ImageServiceWeb.Telemetry do
  @moduledoc """
  OpenTelemetry auto-instrumentation for Phoenix and Bandit.

  This module sets up automatic span creation for:
  - Phoenix router/controller lifecycle
  - Bandit HTTP server (request/response sizes, status codes)
  """

  use Supervisor
  import Telemetry.Metrics
  require Logger

  def start_link(arg) do
    Supervisor.start_link(__MODULE__, arg, name: __MODULE__)
  end

  @impl true
  def init(_arg) do
    children = [
      # Telemetry poller for VM metrics (CPU, memory, etc.)
      {:telemetry_poller, measurements: periodic_measurements(), period: 10_000}
    ]

    :ok = setup_opentelemetry_handlers()
    Supervisor.init(children, strategy: :one_for_one)
  end

  defp setup_opentelemetry_handlers do
    # Phoenix auto-instrumentation (creates spans for controller actions)
    :ok = OpentelemetryPhoenix.setup(adapter: :bandit)

    # Bandit HTTP server instrumentation
    :ok = OpentelemetryBandit.setup()

    Logger.info("[OpenTelemetry] Handlers attached: Phoenix (filtered /metrics), Bandit")
    :ok
  end

  ## Prometheus Metrics (for Grafana dashboards)
  ## ===========================================
  ## Note: PromEx handles most metrics via plugins.
  ## This is for custom business metrics if needed.
  def metrics do
    [
      # Phoenix HTTP metrics (automatic from OpentelemetryPhoenix)
      summary("phoenix.endpoint.stop.duration",
        unit: {:native, :millisecond},
        tags: [:service],
        tag_values: fn _meta -> %{service: "user_svc"} end,
        description: "HTTP request duration at endpoint level"
      ),
      summary("phoenix.router_dispatch.stop.duration",
        unit: {:native, :millisecond},
        tags: [:route, :service],
        tag_values: fn meta ->
          %{
            route: meta[:route] || meta[:request_path] || "unknown",
            service: "user_svc"
          }
        end,
        description: "HTTP request duration per route"
      ),

      # VM metrics (collected by telemetry_poller)
      last_value("vm.memory.total",
        unit: {:byte, :megabyte},
        description: "Total BEAM VM memory"
      ),
      last_value("vm.total_run_queue_lengths.total",
        description: "Scheduler run queue length"
      ),
      last_value("vm.system_counts.process_count",
        description: "Number of Erlang processes"
      )
    ]
  end

  defp periodic_measurements do
    [
      # Add custom periodic measurements if needed
      # Example: {UserSvc.Metrics, :measure_active_users, []}
    ]
  end
end
