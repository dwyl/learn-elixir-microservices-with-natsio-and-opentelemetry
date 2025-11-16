defmodule ImageService.Application do
  use Application

  @moduledoc """
  Image Service Application

  Responsible for image processing operations (PNG to PDF conversion, etc.)

  Utilizes JetStream for asynchronous job handling and communication with other microservices.
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
      {Task, &setup_jetstream/0},
      ImageSvc.BroadwayImageProcessor,
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
        %{
          host: System.get_env("NATS_HOST", "localhost"),
          port: System.get_env("NATS_PORT", "4222") |> String.to_integer()
        }
      ]
    }
  end

  defp setup_jetstream do
    case Process.whereis(:gnat) do
      nil ->
        Process.send_after(self(), :ready, 20)

        receive do
          :ready ->
            setup_jetstream()
        after
          1000 ->
            raise "Timeout waiting for NATS connection"
        end

      pid when is_pid(pid) ->
        :ok = JetstreamSetup.setup_from_config(:image_svc, :gnat)
        Logger.info("[NATS] Jetstream is ready")
    end
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
