defmodule EmailService.NatsConsumer do
  require Logger
  require OpenTelemetry.Tracer, as: Tracer

  def handle_message(%{topic: "email.send", body: binary_body} = message) do
    # Extract trace context from incoming NATS message and attach it
    headers = Map.get(message, :headers, [])
    _token = OtelNats.extract_and_attach(headers)

    Tracer.with_span "EmailService.NatsConsumer.email.send" do
      %Mcsv.V2.UserRequest{type: type_enum, name: name, email: email} =
        Mcsv.V2.UserRequest.decode(binary_body)

      deliver_and_confirm(type_enum, email, name)
    end
  end

  defp enum_to_string(:EMAIL_TYPE_WELCOME), do: "welcome"
  defp enum_to_string(:EMAIL_TYPE_NOTIFICATION), do: "notification"

  defp deliver_and_confirm(type_enum, email, name) do
    type = enum_to_string(type_enum)

    case type do
      "welcome" ->
        Emails.UserEmail.welcome_email(email, name)
        |> EmailService.Mailer.deliver()

      "notification" ->
        Emails.UserEmail.notification_email(
          email,
          name,
          "new notification",
          "a notification"
        )
        |> EmailService.Mailer.deliver()
    end

    Logger.info("[Email][DeliveryController]: New email sent to #{email}")

    response_binary =
      %Mcsv.V2.EmailResponse{
        success: true,
        user_email: email,
        message: "[Email][DeliveryController] New email sent to #{email}"
      }
      |> Mcsv.V2.EmailResponse.encode()

    # Inject trace context into outgoing message
    trace_headers = OtelNats.inject()
    :ok = Gnat.pub(:gnat, "user.email.delivered", response_binary, headers: trace_headers)
  end
end
