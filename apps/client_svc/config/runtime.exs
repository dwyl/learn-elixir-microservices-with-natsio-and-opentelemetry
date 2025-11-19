import Config

# Runtime configuration for client_svc
# All values can be overridden via environment variables

# HTTP Port
port = System.get_env("CLIENT_SVC_PORT", "8085") |> String.to_integer()

expiry_bucket_retention =
  System.get_env("IMAGE_BUCKET_MAX_AGE", "3600") |> String.to_integer()

image_bucket =
  System.get_env("IMAGE_BUCKET", "msvc-images")

access_key_id =
  System.get_env("MINIO_ROOT_USER", "minioadmin")

secret_access_key =
  System.get_env("MINIO_ROOT_PASSWORD", "minioadmin")

object_storage_endpoint =
  System.get_env("MINIO_ENDPOINT", "http://127.0.0.1:9000")

region =
  System.get_env("AWS_REGION", "us-east-1")

nats_host =
  System.get_env("NATS_HOST", "localhost")

nats_port =
  System.get_env("NATS_PORT", "4222") |> String.to_integer()

otel_exporter_otlp_protocol =
  System.get_env("OTEL_EXPORTER_OTLP_PROTOCOL", "http")

otel_exporter_otlp_endpoint =
  System.get_env("OTEL_EXPORTER_OTLP_ENDPOINT")

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
  port: port

config :client_svc, :s3,
  object_storage_endpoint: object_storage_endpoint,
  image_bucket: image_bucket

config :client_svc, :nats,
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
