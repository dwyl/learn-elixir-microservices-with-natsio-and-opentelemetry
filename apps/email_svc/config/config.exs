import Config

# NOTE: Runtime configuration (ports, URLs, credentials) is in config/runtime.exs
# This file only contains compile-time configuration

# Configure Email Service
config :email_svc,
  ecto_repos: []

# Configure JetStream streams for this service
config :email_svc, :jetstream_streams, [
  %{
    name: "EMAILS",
    subjects: ["email.>"],
    consumers: [
      %{name: "welcome_mailer", filter_subject: "email.welcome", deliver_policy: "all"},
      %{name: "notification_mailer", filter_subject: "email.notification", deliver_policy: "all"}
    ]
  }
]

# Configure Swoosh Mailer (adapter is in runtime.exs)
config :email_svc, EmailService.Mailer, adapter: Swoosh.Adapters.Local

# Disable Swoosh API client (not needed for Local adapter)
config :swoosh, :api_client, false
config :swoosh, :json_library, JSON

config :email_svc, EmailService.PromEx,
  disabled: false,
  manual_metrics_start_delay: :no_delay,
  drop_metrics_groups: [],
  grafana: :disabled,
  metrics_server: :disabled

# OpenTelemetry Configuration
config :opentelemetry,
  span_processor: :batch,
  traces_exporter: :otlp,
  resource: %{service: "email_svc"}

# Logger configuration - uses Docker Loki driver for log shipping
config :logger, level: :info
# Add service name to all logs
config :logger, :default_formatter, metadata: [:service]

import_config "#{config_env()}.exs"
