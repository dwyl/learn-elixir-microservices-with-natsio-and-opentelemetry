defmodule UserSvc.Application do
  use Application
  # require OpenTelemetry.Tracer

  @moduledoc """
  Entry point
  """
  require Logger

  defp image_bucket, do: Application.get_env(:user_svc, :image_bucket)
  defp loki_chunks, do: Application.get_env(:user_svc, :loki_chunks)

  @impl true
  def start(_type, _args) do
    port = Application.get_env(:user_svc, :port, 8081)
    Logger.info("Starting USER Service on port #{port}")
    ensure_minio_bucket()

    children = [
      UserSvc.PromEx,
      {Task.Supervisor, name: UserSvc.TaskSupervisor},
      UserSvc.MinIOCleaner,
      {Cluster.Supervisor, [topologies(), [name: UserSvc.Application.ClusterSupervisor]]},
      {Gnat.ConnectionSupervisor, gnat_supervisor_settings()},
      {Gnat.ConsumerSupervisor, consumer_supervisor_settings()},
      UserSvcWeb.Telemetry,
      UserSvcWeb.Endpoint
    ]

    opts = [strategy: :one_for_one, name: UserSvc.Supervisor]
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
      consuming_function: {UserSvc.NatsConsumer, :handle_message},
      subscription_topics: [
        %{topic: "user.email.create"},
        %{topic: "user.email.delivered"},
        %{topic: "user.convert.to_pdf"},
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

  defp ensure_minio_bucket do
    # buckets = ["msvc-images", "loki-chunks"]
    buckets = [image_bucket(), loki_chunks()]

    Logger.info("[MinIO] Ensuring bucket '#{image_bucket()}' exists")

    [:ok, :ok] =
      for bucket <- buckets do
        case ExAws.S3.head_bucket(bucket) |> ExAws.request() do
          {:ok, _} ->
            Logger.info("[MinIO] Bucket '#{bucket}' already exists")
            :ok

          {:error, {:http_error, 404, _}} ->
            Logger.info("[MinIO] Creating bucket '#{bucket}'")

            case ExAws.S3.put_bucket(bucket, "us-east-1") |> ExAws.request() do
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
