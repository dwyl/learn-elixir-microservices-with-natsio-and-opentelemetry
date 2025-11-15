defmodule EmailService.Application do
  use Application

  @moduledoc false

  require Logger

  @impl true
  def start(_type, _args) do
    port = Application.get_env(:email_svc, :port, 8083)
    Logger.info("Starting EMAIL Server on port #{port}")

    children = [
      EmailService.PromEx,
      EmailServiceWeb.Telemetry,
      {Cluster.Supervisor, [topologies(), [name: EmailService.Application.ClusterSupervisor]]},
      {Gnat.ConnectionSupervisor, gnat_supervisor_settings()},
      {Gnat.ConsumerSupervisor, consumer_supervisor_settings()},
      EmailServiceWeb.Endpoint
    ]

    opts = [strategy: :one_for_one, name: EmailService.Supervisor]
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
      consuming_function: {EmailService.NatsConsumer, :handle_message},
      subscription_topics: [
        %{topic: "email.send"}
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
