defmodule Broadway.Emails.Welcome do
  use Broadway
  require Logger
  require OpenTelemetry.Tracer, as: Tracer

  alias Broadway.Message

  def start_link(_opts) do
    Broadway.start_link(
      __MODULE__,
      name: __MODULE__,
      producer: [
        module: {
          OffBroadway.Jetstream.Producer,
          connection_name: :gnat,
          stream_name: "EMAILS",
          consumer_name: "welcome_mailer",
          # Fetch more messages per batch for better throughput
          max_number_of_messages: 50,
          # Check for messages more frequently (10ms vs 100ms) for lower latency
          receive_interval: 10
        },
        # Increase producer concurrency for better message fetching
        concurrency: 2
      ],
      processors: [
        # Increase processor concurrency for parallel email sending
        mailer: [concurrency: 4]
      ]
    )
  end

  @impl true
  def handle_message(:mailer, msg, _ctx) do
    Logger.info("[Broadway.Welcome] Processing welcome email message")

    # Extract trace context from message headers
    headers = msg.metadata[:headers] || []
    _token = OtelNats.extract_and_attach(headers)

    %Broadway.Message{data: data} = msg

    # Process the email within a span
    result =
      Tracer.with_span "Broadway.Emails.Welcome.handle_message" do
        perform_email_delivery(data)
      end

    case result do
      :ok ->
        Logger.info("[Broadway.Welcome] Email sent successfully")
        # Return message unchanged - Broadway will ACK automatically
        msg

      {:error, reason} ->
        Logger.error("[Broadway.Welcome] Email delivery failed: #{inspect(reason)}")
        # Failed message - Broadway will NACK for retry
        Message.failed(msg, reason)
    end
  end

  defp perform_email_delivery(binary_body) do
    %Mcsv.V2.UserRequest{} = req = Mcsv.V2.UserRequest.decode(binary_body)

    Logger.info("[Broadway.Welcome] Sending welcome email to #{req.email}")

    try do
      # Send the welcome email
      Emails.Templates.welcome_email(req.email, req.name)
      |> EmailService.Mailer.deliver()

      # Build success response
      response_binary =
        %Mcsv.V2.EmailResponse{
          success: true,
          user_email: req.email,
          message: "[Email] Welcome email sent to #{req.email}"
        }
        |> Mcsv.V2.EmailResponse.encode()

      # Inject trace context into outgoing message
      trace_headers = OtelNats.inject_with_link()
      :ok = Gnat.pub(:gnat, "user.email.delivered", response_binary, headers: trace_headers)

      Logger.info("[Broadway.Welcome] Welcome email sent to #{req.email}")
      :ok
    rescue
      error ->
        Logger.error(
          "[Broadway.Welcome] Error sending email: #{inspect(error)}\n#{Exception.format_stacktrace()}"
        )

        OpenTelemetry.Tracer.set_status(:error, "Email delivery failed")
        {:error, :email_delivery_failed}
    end
  end
end
