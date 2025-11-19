defmodule EmailService.Application do
  use Application

  @moduledoc """
  We defined two pullconsumers here: Welcome and Notification.

  The Welcome consumer handles sending welcome emails to new users,
  while the Notification consumer manages sending various notifications.

  We need to define two streams in JetStream for these consumers to function properly:

  1. EMAILS Stream: This stream will handle all email-related messages, including welcome emails and notifications.
  2. NOTIFICATIONS Stream: This stream will specifically manage notification messages.
  """

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
      # blocking jetstream setup task
      %{
        id: JetstreamSetup,
        start: {Task, :start_link, [fn -> setup_jetstream() end]},
        restart: :transient
      },
      Broadway.Emails.Welcome,
      Broadway.Emails.Notification,
      EmailServiceWeb.Endpoint
    ]

    opts = [strategy: :one_for_one, name: EmailService.Supervisor]
    Supervisor.start_link(children, opts)
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
        :ok = JetstreamSetup.setup_from_config(:email_svc, :gnat)
        Logger.info("[NATS] Jetstream is ready")
    end
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
