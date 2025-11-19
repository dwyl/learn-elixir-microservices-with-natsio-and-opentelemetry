defmodule EmailService.NatsConsumer do
  require Logger
  require OpenTelemetry.Tracer, as: Tracer

  def deliver_and_confirm(type_enum, email, name) do
    type = enum_to_string(type_enum)

    case type do
      "welcome" ->
        Emails.Templates.welcome_email(email, name)
        |> EmailService.Mailer.deliver()

      "notification" ->
        Emails.Templates.notification_email(
          email,
          name,
          "new notification",
          "a notification"
        )
        |> EmailService.Mailer.deliver()
    end

    Logger.info("[Email]: New email #{type} sent to #{email}")

    response_binary =
      %Mcsv.V2.EmailResponse{
        success: true,
        user_email: email,
        message: "[Email] New email sent to #{email}"
      }
      |> Mcsv.V2.EmailResponse.encode()

    # Inject trace context with span link into outgoing message
    trace_headers = OtelNats.inject_with_link()
    :ok = Gnat.pub(:gnat, "user.email.delivered", response_binary, headers: trace_headers)
  end

  defp enum_to_string(:EMAIL_TYPE_WELCOME), do: "welcome"
  defp enum_to_string(:EMAIL_TYPE_NOTIFICATION), do: "notification"
end
