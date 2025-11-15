import Config

# Runtime configuration for client_svc
# All values can be overridden via environment variables

# HTTP Port
port = System.get_env("CLIENT_SVC_PORT", "8085") |> String.to_integer()

config :client_svc, ClientServiceWeb.Endpoint,
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

config :client_svc,
  port: port,
  # Use USER_SVC_URL from docker-compose (http://user_svc:8081) or fallback to localhost for dev
  user_svc_base_url:
    System.get_env("USER_SVC_URL", "http://127.0.0.1:#{System.get_env("USER_SVC_PORT", "8081")}"),
  user_endpoints: %{
    create: "/user_svc/create_email/v1",
    convert_image: "/user_svc/convert_image/v1"
  }

config :client_svc, :nats,
  host: System.get_env("NATS_HOST", "nats-server"),
  port: System.get_env("NATS_PORT", "4222") |> String.to_integer()

# Determine OTLP protocol from environment variable
# Options: "http" (default) or "grpc" (production)
otlp_protocol =
  case System.get_env("OTEL_EXPORTER_OTLP_PROTOCOL", "http") do
    "grpc" ->
      :grpc

    "http" ->
      :http_protobuf

    other ->
      IO.warn("Unknown OTLP protocol '#{other}', defaulting to :http_protobuf")
      :http_protobuf
  end

otlp_endpoint =
  case System.get_env("OTEL_EXPORTER_OTLP_ENDPOINT") do
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
