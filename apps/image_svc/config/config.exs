import Config

# This file only contains compile-time configuration

# PromEx configuration for Prometheus metrics--------------------------
config :image_svc, ImageService.PromEx,
  disabled: false,
  manual_metrics_start_delay: :no_delay,
  drop_metrics_groups: [],
  grafana: :disabled,
  metrics_server: :disabled

# Configure JetStream streams for this service
config :image_svc, :jetstream_streams, [
  %{
    name: "IMAGES",
    subjects: ["image.convert.>"],
    consumers: [
      %{
        name: "pdf_processor",
        filter_subject: "image.convert.to_pdf",
        deliver_policy: "all"
      }
    ]
  }
]

# OpenTelemetry -------------------------------------------------------
config :opentelemetry,
  span_processor: :batch,
  traces_exporter: :otlp,
  resource: %{service: "image_svc"}

config :opentelemetry_ecto, :tracer, repos: [ImageService.Repo]

# Add service name to all logs
config :logger, :default_formatter, metadata: [:service, :span_id, :trace_id]

config :phoenix, :json_library, Jason

import_config "#{config_env()}.exs"
