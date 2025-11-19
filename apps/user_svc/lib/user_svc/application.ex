defmodule UserService.Application do
  use Application
  # require OpenTelemetry.Tracer

  @moduledoc """
  Entry point
  """
  require Logger

  @impl true
  def start(_type, _args) do
    port = Application.get_env(:user_svc, :port, 8081)
    Logger.info("Starting USER Service on port #{port}")
    ensure_minio_buckets()

    children = [
      UserService.PromEx,
      {Task.Supervisor, name: UserService.TaskSupervisor},
      UserService.MinIOCleaner,
      {Cluster.Supervisor, [topologies(), [name: UserService.ClusterSupervisor]]},
      {Gnat.ConnectionSupervisor, gnat_supervisor_settings()},
      {Gnat.ConsumerSupervisor, consumer_supervisor_settings()},
      UserServiceWeb.Telemetry,
      UserServiceWeb.Endpoint
    ]

    opts = [strategy: :one_for_one, name: UserService.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp gnat_supervisor_settings do
    %{
      name: :gnat,
      backoff_period: 4_000,
      connection_settings: [
        %{host: nats_host(), port: nats_port()}
      ]
    }
  end

  defp consumer_supervisor_settings do
    %{
      connection_name: :gnat,
      consuming_function: {UserService.NatsConsumer, :handle_message},
      subscription_topics: [
        %{topic: "user.email.create"},
        %{topic: "user.email.delivered"},
        %{topic: "user.convert.binary.to_pdf"},
        %{topic: "user.convert.url.to_pdf"},
        %{topic: "user.image.converted"}
      ]
    }
  end

  defp nats_host do
    System.get_env("NATS_HOST", "localhost")
  end

  defp nats_port do
    System.get_env("NATS_PORT", "4222") |> String.to_integer()
  end

  defp topologies do
    [
      msvc_cluster: [
        strategy: Cluster.Strategy.Epmd,
        config: [
          hosts: [
            :"user_svc@user_svc.msvc",
            :"job_svc@job_svc.msvc",
            :"image_svc@image_svc.msvc",
            :"email_svc@email_svc.msvc"
          ]
        ]
      ]
    ]
  end

  defp image_bucket do
    Application.get_env(:user_svc, :s3)
    |> Keyword.get(:image_bucket, "msvc-images")
  end

  defp loki_chunks do
    Application.get_env(:user_svc, :s3)
    |> Keyword.get(:loki_chunks, "loki-chunks")
  end

  defp access_key_id do
    Application.get_env(:user_svc, :s3)
    |> Keyword.get(:access_key_id, "minioadmin")
  end

  defp secret_access_key do
    Application.get_env(:user_svc, :s3)
    |> Keyword.get(:secret_access_key, "minioadmin")
  end

  defp ensure_minio_buckets do
    # buckets = ["msvc-images", "loki-chunks"]
    buckets = [image_bucket(), loki_chunks()]

    object_storage_endpoint =
      Application.get_env(:user_svc, :s3)
      |> Keyword.get(:object_storage_endpoint, "http://localhost:9000")

    s3_options = [
      access_key_id: access_key_id(),
      secret_access_key: secret_access_key()
    ]

    Logger.info("[MinIO] Ensuring bucket '#{image_bucket()}' exists")

    req =
      Req.new()
      |> ReqS3.attach(
        aws_endpoint_url_s3: object_storage_endpoint,
        aws_sigv4: s3_options
      )

    [:ok, :ok] =
      for bucket <- buckets do
        case Req.get(req, url: "s3://#{bucket}") do
          {:ok, %Req.Response{status: 200}} ->
            Logger.info("[MinIO] Bucket '#{bucket}' already exists")
            :ok

          {:ok, %Req.Response{status: 403}} ->
            Logger.info("[MinIO] Creating bucket '#{bucket}'")

            case Req.put(req, url: "s3://#{bucket}") do
              {:ok, _} ->
                Logger.info("[MinIO] Bucket '#{bucket}' created successfully")
                :ok

              {:error, reason} ->
                Logger.error("[MinIO] Failed to create bucket: #{inspect(reason)}")
                {:error, reason}
            end
        end
      end
  end
end
