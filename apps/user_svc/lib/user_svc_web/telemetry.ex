defmodule UserServiceWeb.Telemetry do
  @moduledoc """
  OpenTelemetry and Telemetry setup for user_svc.

  This module:
  - Attaches OpenTelemetry handlers for Phoenix, Bandit, and Req for automatic span creation
  - Defines Prometheus metrics (via TelemetryMetricsPrometheus)
  - Starts telemetry_poller for VM metrics
  """

  use Supervisor
  import Telemetry.Metrics
  require Logger

  def start_link(arg) do
    Supervisor.start_link(__MODULE__, arg, name: __MODULE__)
  end

  @impl true
  def init(_arg) do
    Logger.info("[UserSvc.Telemetry] Setting up OpenTelemetry instrumentation")

    children = [
      # Telemetry poller for VM metrics (CPU, memory, etc.)
      {:telemetry_poller, measurements: periodic_measurements(), period: 10_000}
    ]

    :ok = setup_opentelemetry_handlers()

    Supervisor.init(children, strategy: :one_for_one)
  end

  ## OpenTelemetry Setup -------------------------------------------

  defp setup_opentelemetry_handlers do
    # Creates spans for every HTTP request with route, method, status
    :ok = OpentelemetryPhoenix.setup(adapter: :bandit)

    :ok = OpentelemetryBandit.setup(opt_in_attrs: [])

    Logger.info("[OpenTelemetry] Handlers attached: Phoenix, Bandit")
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
