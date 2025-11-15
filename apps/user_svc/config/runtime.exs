import Config

# env = System.get_env("MIX_ENV", "dev")

# HTTP Port
port = System.get_env("USER_SVC_PORT", "8081") |> String.to_integer()

config :user_svc, UserSvcWeb.Endpoint,
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

config :user_svc,
  port: port,
  # Use *_URL from docker-compose or fallback to localhost for dev
  user_svc_base_url:
    System.get_env("USER_SVC_URL", "http://127.0.0.1:#{System.get_env("USER_SVC_PORT", "8081")}"),
  job_svc_base_url:
    System.get_env("JOB_SVC_URL", "http://127.0.0.1:#{System.get_env("JOB_SVC_PORT", "8082")}"),
  client_svc_base_url:
    System.get_env(
      "CLIENT_SVC_URL",
      "http://127.0.0.1:#{System.get_env("CLIENT_SVC_PORT", "8085")}"
    ),
  job_svc_endpoints: %{
    convert_image: "/job_svc/convert_image/v1",
    enqueue_email: "/job_svc/enqueue_email/v1"
  },
  client_svc_endpoints: %{
    pdf_ready: "/client_svc/pdf_ready/v1",
    receive_notification: "/client_svc/receive_email_notification/v1"
  },
  user_svc_endpoints: %{
    image_loader: "/user_svc/image_loader/v1"
  },
  loki_chunks: System.get_env("LOKI_CHUNKS", "loki-chunks"),
  image_bucket: System.get_env("IMAGE_BUCKET", "msvc-images")

# MinIO / S3 Configuration
config :ex_aws,
  access_key_id: System.get_env("MINIO_ROOT_USER", "minioadmin"),
  secret_access_key: System.get_env("MINIO_ROOT_PASSWORD", "minioadmin"),
  region: System.get_env("AWS_REGION", "us-east-1"),
  json_codec: Jason

config :ex_aws, :s3,
  scheme: System.get_env("MINIO_SCHEME", "http://"),
  host: System.get_env("MINIO_HOST", "127.0.0.1"),
  port: System.get_env("MINIO_PORT", "9000") |> String.to_integer(),
  region: System.get_env("AWS_REGION", "us-east-1")

config :user_svc, :nats,
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
