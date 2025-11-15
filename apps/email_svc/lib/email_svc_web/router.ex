defmodule EmailServiceWeb.Router do
  use EmailServiceWeb, :router
  @moduledoc false

  # Health check endpoints
  get("/health", HealthController, :check)
  head("/health", HealthController, :check)

  # Prometheus metrics endpoint. Replaced by PromEx plug.
  # get "/metrics" do
  #   metrics = TelemetryMetricsPrometheus.Core.scrape(:email_svc_metrics)

  #   conn
  #   |> put_resp_content_type("text/plain; version=0.0.4")
  #   |> send_resp(200, metrics)
  # end
end
