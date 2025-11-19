defmodule Broadway.Emails.Notification do
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
          consumer_name: "notification_mailer",
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
    Logger.info("[Broadway.Notification] Processing notification email message")

    # Extract trace context from message headers
    headers = msg.metadata[:headers] || []
    _token = OtelNats.extract_and_attach(headers)

    %Broadway.Message{data: data} = msg

    # Process the email within a span
    result =
      Tracer.with_span "Broadway.Emails.Notification.handle_message" do
        perform_email_delivery(data)
      end

    case result do
      :ok ->
        Logger.info("[Broadway.Notification] Email sent successfully")
        # Return message unchanged - Broadway will ACK automatically
        msg

      {:error, reason} ->
        Logger.error("[Broadway.Notification] Email delivery failed: #{inspect(reason)}")
        # Failed message - Broadway will NACK for retry
        Message.failed(msg, reason)
    end
  end

  defp perform_email_delivery(binary_body) do
    %Mcsv.V2.UserRequest{} = req = Mcsv.V2.UserRequest.decode(binary_body)

    Logger.info("[Broadway.Notification] Sending notification email to #{req.email}")

    try do
      # Send the notification email
      Emails.Templates.notification_email(
        req.email,
        req.name,
        "new notification",
        "a notification"
      )
      |> EmailService.Mailer.deliver()

      # Build success response
      response_binary =
        %Mcsv.V2.EmailResponse{
          success: true,
          user_email: req.email,
          message: "[Email] Notification email sent to #{req.email}"
        }
        |> Mcsv.V2.EmailResponse.encode()

      # Inject trace context into outgoing message
      trace_headers = OtelNats.inject_with_link()
      :ok = Gnat.pub(:gnat, "user.email.delivered", response_binary, headers: trace_headers)

      Logger.info("[Broadway.Notification] Notification email sent to #{req.email}")
      :ok
    rescue
      error ->
        Logger.error(
          "[Broadway.Notification] Error sending email: #{inspect(error)}\n#{Exception.format_stacktrace()}"
        )

        OpenTelemetry.Tracer.set_status(:error, "Email delivery failed")
        {:error, :email_delivery_failed}
    end
  end
end
