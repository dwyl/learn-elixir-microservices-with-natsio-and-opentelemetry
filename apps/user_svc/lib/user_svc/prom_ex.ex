defmodule UserService.PromEx do
  @moduledoc """
  To finish setting up PromEx:

  1. Update your configuration
  2. Add this module to your application supervision tree.
  3. Update your `endpoint.ex` file to expose your metrics (or configure a standalone
     server using the `:metrics_server` config options). Be sure to put this plug before your `Plug.Telemetry` entry so that you can avoid having calls to your `/metrics` endpoint create their own metrics and logs which can pollute your logs/metrics given that Prometheus will scrape at a regular interval and that can get
  4. Update the list of plugins in the `plugins/0` function return list to reflect your
     application's dependencies. Also update the list of dashboards that are to be uploaded to Grafana in the `dashboards/0` function.
  """

  use PromEx, otp_app: :user_svc

  alias PromEx.Plugins

  @impl true
  def plugins do
    [
      # PromEx built in plugins
      Plugins.Application,
      Plugins.Beam,
      {Plugins.Phoenix, router: UserServiceWeb.Router, endpoint: UserServiceWeb.Endpoint},
      PromExPlugin.OsMetrics,
      PromExPlugin.NatsMetrics
      # Plugins.Ecto,
      # Plugins.Oban,
      # Plugins.PhoenixLiveView,
      # Plugins.Absinthe,
      # Plugins.Broadway,

      # Add your own PromEx metrics plugins
      # UserSvc.Users.PromExPlugin
    ]
  end

  @impl true
  def dashboard_assigns do
    [
      datasource_id: "prometheus",
      default_selected_interval: "30s"
    ]
  end

  @impl true
  def dashboards do
    [
      # PromEx built in Grafana dashboards
      {:prom_ex, "application.json"},
      {:prom_ex, "beam.json"},
      {:prom_ex, "phoenix.json"}
      # {:prom_ex, "ecto.json"},
      # {:prom_ex, "oban.json"},
      # {:prom_ex, "phoenix_live_view.json"},
      # {:prom_ex, "absinthe.json"},
      # {:prom_ex, "broadway.json"},

      # Add your dashboard definitions here with the format: {:otp_app, "path_in_priv"}
      # {:user_svc, "/grafana_dashboards/user_metrics.json"}
    ]
  end
end
