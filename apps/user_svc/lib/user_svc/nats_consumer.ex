defmodule UserSvc.NatsConsumer do
  @moduledoc """
  NATS message handler for user.create events.

  Processes incoming user creation requests from NATS.
  """
  require Logger
  require OpenTelemetry.Tracer, as: Tracer

  @doc """
  Handle incoming NATS messages.
  Called by Gnat.ConsumerSupervisor for each message.
  """
  def handle_message(%{topic: "user.email.create", body: body} = message) do
    # Extract trace context from incoming NATS message and attach it
    headers = Map.get(message, :headers, [])
    _token = OtelNats.extract_and_attach(headers)

    %Mcsv.V3.UserRequest{} =
      req =
      Mcsv.V3.UserRequest.decode(body)

    Tracer.with_span "UserSvc.NatsConsumer.email.create" do
      Logger.info("[NatsConsumer] Received message on email.create")

      # Inject trace context into outgoing message
      trace_headers = OtelNats.inject()

      case req.type do
        :EMAIL_TYPE_WELCOME ->
          :ok = Gnat.pub(:gnat, "email.welcome", body, headers: trace_headers)

        :EMAIL_TYPE_NOTIFICATION ->
          :ok = Gnat.pub(:gnat, "email.notification", body, headers: trace_headers)

        _ ->
          Logger.error("[NatsConsumer] Unknown email type: #{inspect(req.type)}")
          OpenTelemetry.Tracer.set_status(:error, "Unknown email type")
          {:error, :unknown_email_type}
      end
    end
  end

  def handle_message(%{topic: "user.email.delivered"} = message) do
    body = Map.get(message, :body)
    headers = Map.get(message, :headers, [])

    # Extract trace context from incoming NATS message and attach it
    _token = OtelNats.extract_and_attach(headers)

    Tracer.with_span "UserSvc.NatsConsumer.email.delivered" do
      Logger.info("[NatsConsumer] Received message on email.delivered")

      # Inject trace context into outgoing message
      trace_headers = OtelNats.inject()
      :ok = Gnat.pub(:gnat, "client.email.delivered", body, headers: trace_headers)
    end
  end

  def handle_message(%{topic: "user.image.converted", body: body} = message) do
    # Extract trace context from incoming NATS message and attach it
    headers = Map.get(message, :headers, [])
    _token = OtelNats.extract_and_attach(headers)
    link = OtelNats.extract_link(headers)

    # Create span with link to the Image service's conversion span
    span_opts = if link, do: %{links: [link]}, else: %{}

    Tracer.with_span "UserSvc.NatsConsumer.image.converted", span_opts do
      Logger.info("[NatsConsumer] Image converted")

      # Inject trace context into outgoing message (keep the link chain going)
      trace_headers = OtelNats.inject_with_link()
      :ok = Gnat.pub(:gnat, "client.image.converted", body, headers: trace_headers)
    end
  end

  def handle_message(%{topic: "user.convert.to_pdf", body: body} = message) do
    # Extract trace context from incoming NATS message and attach it
    headers = Map.get(message, :headers, [])
    _token = OtelNats.extract_and_attach(headers)

    Tracer.with_span "UserSvc.NatsConsumer.convert.to_pdf" do
      req = Mcsv.V3.ImageConversionRequest.decode(body)

      OpenTelemetry.Tracer.set_attribute("job.id", req.job_id)

      ctx = OpenTelemetry.Ctx.get_current()

      Task.Supervisor.start_child(UserSvc.TaskSupervisor, fn ->
        # inject trace context into new process
        OpenTelemetry.Ctx.attach(ctx)
        store_image(req)
      end)

      # Inject trace context for outgoing message
      trace_headers = OtelNats.inject()
      :ok = forward_to_job_svc(req, trace_headers)
      Logger.info("[NatsConsumer] Image conversion request sent to Image")
    end
  end

  defp store_image(request) do
    format = if request.input_format == "", do: "png", else: request.input_format

    case ImageStorage.store(request.image_data, request.user_id, format) do
      {:ok, {_job_id, _presigned_url, _size}} ->
        :ok

      {:error, reason} ->
        OpenTelemetry.Tracer.set_status(:error, "Storage failed")
        {:error, reason}
    end
  end

  defp forward_to_job_svc(req, trace_headers) do
    img =
      %{req | image_url: nil}
      |> Mcsv.V3.ImageConversionRequest.encode()

    :ok = Gnat.pub(:gnat, "image.convert.to_pdf", img, headers: trace_headers)
  end
end
