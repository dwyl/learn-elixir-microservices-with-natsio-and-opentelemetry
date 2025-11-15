defmodule ClientService.NatsConsumer do
  require Logger
  require OpenTelemetry.Tracer, as: Tracer

  def handle_message(%{topic: "client.email.delivered", body: body} = message) do
    # Extract trace context from incoming NATS message and attach it
    headers = Map.get(message, :headers, [])
    _token = OtelNats.extract_and_attach(headers)

    Tracer.with_span "ClientService.NatsConsumer.email.delivered" do
      resp = Mcsv.V2.EmailResponse.decode(body)
      Logger.info("[Client] Email delivered for user: #{resp.user_email}")
    end
  end

  def handle_message(%{topic: "client.image.converted", body: body} = message) do
    # Extract trace context from incoming NATS message and attach it
    headers = Map.get(message, :headers, [])
    _token = OtelNats.extract_and_attach(headers)

    Tracer.with_span "ClientService.NatsConsumer.image.converted" do
      resp = Mcsv.V2.ImageConversionResponse.decode(body)
      Logger.info("[Client] Received converted image: #{resp.pdf_url}")
    end
  end
end
