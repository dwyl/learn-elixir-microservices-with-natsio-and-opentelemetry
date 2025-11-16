defmodule PullConsumer.Notification do
  use Jetstream.PullConsumer
  require OpenTelemetry.Tracer, as: Tracer

  def start_link([]) do
    Jetstream.PullConsumer.start_link(__MODULE__, [])
  end

  @impl true
  def init([]) do
    {:ok, nil,
     connection_name: :gnat, stream_name: "EMAILS", consumer_name: "notification_mailer"}
  end

  @impl true
  def handle_message(message, state) do
    headers = message.headers || []
    _token = OtelNats.extract_and_attach(headers)

    Tracer.with_span "PullConsumer.Notification.handle_message" do
      %Mcsv.V2.UserRequest{} =
        req =
        Mcsv.V2.UserRequest.decode(message.body)

      EmailService.NatsConsumer.deliver_and_confirm(req.type, req.email, req.name)
    end

    {:ack, state}
  end
end
