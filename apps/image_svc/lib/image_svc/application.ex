defmodule ImageService.Application do
  use Application

  @moduledoc """
  Image Service Application

  Responsible for image processing operations (PNG to PDF conversion, etc.)
  Receives requests via HTTP and processes them using:
  - ImageMagick for image format detection, metadata extraction, and PDF conversion
  - Ghostscript (used internally by ImageMagick for PDF rendering)
  """

  require Logger

  @impl true
  def start(_type, _args) do
    ImageMagick.check()

    children = [
      # PromEx must start before Repo to capture Ecto init events
      ImageService.PromEx,
      # OpenTelemetry auto-instrumentation (must be first)
      ImageSvcWeb.Telemetry,
      {Cluster.Supervisor, [topologies(), [name: ImageService.Application.ClusterSupervisor]]},
      {Gnat.ConnectionSupervisor, gnat_supervisor_settings()},
      {Gnat.ConsumerSupervisor, consumer_supervisor_settings()},
      ImageSvcWeb.Endpoint
    ]

    opts = [strategy: :one_for_one, name: ImageService.Supervisor]
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
      consuming_function: {ImageSvc.NatsConsumer, :handle_message},
      subscription_topics: [
        %{topic: "image.convert.to_pdf"}
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
end
