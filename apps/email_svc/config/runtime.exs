import Config

# Runtime configuration for email_svc

# HTTP Port
port = System.get_env("EMAIL_SVC_PORT", "8083") |> String.to_integer()

nats_host =
  System.get_env("NATS_HOST", "localhost")

nats_port =
  System.get_env("NATS_PORT", "4222") |> String.to_integer()

otel_exporter_otlp_protocol =
  System.get_env("OTEL_EXPORTER_OTLP_PROTOCOL", "http")

otel_exporter_otlp_endpoint =
  System.get_env("OTEL_EXPORTER_OTLP_ENDPOINT")

config :email_svc, EmailServiceWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  http: [
    # Bind to all interfaces for Docker networking
    ip: {0, 0, 0, 0},
    port: port
  ],
  server: true,
  check_origin: false,
  secret_key_base: "lSELLkV2qXzO3PbrZjubtnS84cvDgItzZ3cuQMlmRrM/f5Iy0YHJgn/900qLm7/a"

config :email_svc,
  port: port

config :email_svc, :nats,
  host: nats_host,
  port: nats_port

# Determine OTLP protocol from environment variable
# Options: "http" (default) or "grpc" (production)
otlp_protocol =
  case otel_exporter_otlp_protocol do
    "grpc" ->
      :grpc

    "http" ->
      :http_protobuf

    other ->
      IO.warn("Unknown OTLP protocol '#{other}', defaulting to :http_protobuf")
      :http_protobuf
  end

otlp_endpoint =
  case otel_exporter_otlp_endpoint do
    nil -> "http://127.0.0.1:4318"
    endpoint -> endpoint
  end

config :opentelemetry_exporter,
  otlp_protocol: otlp_protocol,
  otlp_endpoint: otlp_endpoint

# Logger Configuration
log_level = System.get_env("LOG_LEVEL", "info") |> String.to_atom()

config :logger,
  level: log_level

# Optionally configure JSON logging
if System.get_env("LOG_FORMAT") == "json" do
  config :logger, :default_handler,
    formatter:
      {LoggerJSON.Formatters.Basic,
       metadata: [
         :request_id,
         :service,
         :trace_id,
         :span_id,
         :user_id,
         :duration
       ]}
end

# Swoosh Mailer - Local adapter (no SMTP needed!)
# For production, you can switch to SMTP, SendGrid, Mailgun, etc. via env vars
adapter_module =
  case System.get_env("MAILER_ADAPTER", "local") do
    "local" -> Swoosh.Adapters.Local
    "smtp" -> Swoosh.Adapters.SMTP
    "sendgrid" -> Swoosh.Adapters.Sendgrid
    _ -> Swoosh.Adapters.Local
  end

config :email_svc, EmailService.Mailer, adapter: adapter_module

# SMTP config (only used if MAILER_ADAPTER=smtp)
if adapter_module == Swoosh.Adapters.SMTP do
  config :email_svc, EmailService.Mailer,
    relay: System.get_env("SMTP_RELAY", "smtp.gmail.com"),
    username: System.get_env("SMTP_USERNAME"),
    password: System.get_env("SMTP_PASSWORD"),
    port: System.get_env("SMTP_PORT", "587") |> String.to_integer(),
    tls: :always
end
