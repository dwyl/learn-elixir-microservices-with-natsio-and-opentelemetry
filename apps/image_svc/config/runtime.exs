import Config

port =
  System.get_env("IMAGE_SVC_PORT", "8084") |> String.to_integer()

loki_chunks =
  System.get_env("LOKI_CHUNKS", "loki-chunks")

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

config :image_svc, ImageServiceWeb.Endpoint,
  adapter: Bandit.PhoenixAdapter,
  url: [host: "localhost"],
  http: [
    # Bind to all interfaces for Docker networking
    ip: {0, 0, 0, 0},
    port: port
  ],
  server: true,
  check_origin: false,
  secret_key_base: "lSELLkV2qXzO3PbrZjubtnS84cvDgItzZ3cuQMlmRrM/f5Iy0YHJgn/900qLm7/a"

config :image_svc,
  image_bucket: image_bucket

# MinIO / S3 Configuration
config :ex_aws,
  access_key_id: access_key_id,
  secret_access_key: secret_access_key,
  region: region,
  json_codec: Jason

config :ex_aws, :s3,
  scheme: System.get_env("MINIO_SCHEME", "http://"),
  host: System.get_env("MINIO_HOST", "127.0.0.1"),
  port: System.get_env("MINIO_PORT", "9000") |> String.to_integer(),
  region: System.get_env("AWS_REGION", "us-east-1")

config :image_svc, :s3,
  object_storage_endpoint: object_storage_endpoint,
  loki_chunks: loki_chunks,
  image_bucket: image_bucket,
  expiry_bucket_retention: expiry_bucket_retention,
  access_key_id: access_key_id,
  secret_access_key: secret_access_key,
  region: region,
  json_codec: Jason,
  scheme: System.get_env("MINIO_SCHEME", "http://"),
  host: System.get_env("MINIO_HOST", "127.0.0.1"),
  port: System.get_env("MINIO_PORT", "9000") |> String.to_integer(),
  region: System.get_env("AWS_REGION", "us-east-1")

# Determine OTLP protocol from environment variable------------------------
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

# Logger configuration - uses Docker Loki driver for log shipping------------------------
config :logger,
  level: System.get_env("LOG_LEVEL", "info") |> String.to_atom()

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
