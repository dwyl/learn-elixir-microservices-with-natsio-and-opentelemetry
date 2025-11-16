defmodule ClientService.Application do
  use Application

  @moduledoc """
  The Client Service Application sets:
  - up OpenTelemetry instrumentation and PromEx metrics
  - a cluster supervisor for node clustering using EPMD with hardcoded service nodes
  - starts the Phoenix Endpoint for HTTP requests: "/health" and "/metrics"
  - supervises NATS connections and consumers for handling incoming messages related to email delivery and image conversion. We used the **push** model here since the Client Service primarily receives notifications rather than processing requests.
  """

  require Logger

  def start(_type, _args) do
    children = [
      ClientService.PromEx,
      ClientServiceWeb.Telemetry,
      {Cluster.Supervisor, [topologies(), [name: ClientService.ClusterSupervisor]]},
      {Gnat.ConnectionSupervisor, gnat_supervisor_settings()},
      {Gnat.ConsumerSupervisor, consumer_supervisor_settings()},
      ClientServiceWeb.Endpoint
    ]

    opts = [strategy: :one_for_one, name: ClientService.Supervisor]
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

  defp consumer_supervisor_settings do
    %{
      connection_name: :gnat,
      consuming_function: {ClientService.NatsConsumer, :handle_message},
      subscription_topics: [
        %{topic: "client.email.delivered"},
        %{topic: "client.image.converted"}
      ]
    }
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
