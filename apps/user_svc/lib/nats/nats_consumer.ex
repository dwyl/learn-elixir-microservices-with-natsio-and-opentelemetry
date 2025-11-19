defmodule UserService.NatsConsumer do
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
    link = OtelNats.extract_link(headers)

    # Create span with link to the Email service's delivery span
    span_opts = if link, do: %{links: [link]}, else: %{}

    Tracer.with_span "UserSvc.NatsConsumer.email.delivered", span_opts do
      Logger.info("[NatsConsumer] Received message on email.delivered")

      # Inject trace context with link into outgoing message (keep the link chain going)
      trace_headers = OtelNats.inject_with_link()
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

  def handle_message(%{topic: "user.convert.binary.to_pdf", body: body} = message) do
    # Extract trace context from incoming NATS message and attach it
    headers = Map.get(message, :headers, [])
    _token = OtelNats.extract_and_attach(headers)

    Tracer.with_span "UserSvc.NatsConsumer.convert.to_pdf" do
      req = Mcsv.V3.ImageConversionRequest.decode(body)

      ctx = OpenTelemetry.Ctx.get_current()

      Task.Supervisor.start_child(
        UserService.TaskSupervisor,
        fn ->
          # inject trace context into new process
          OpenTelemetry.Ctx.attach(ctx)
          :ok = store_image(req)
          :ok
        end,
        restart: :transient
      )

      # Inject trace context for outgoing message
      trace_headers = OtelNats.inject()
      :ok = forward_binary_to_image_svc(req, trace_headers)
      :ok
    end
  end

  def handle_message(%{topic: "user.convert.url.to_pdf", body: body} = message) do
    # Extract trace context from incoming NATS message and attach it
    headers = Map.get(message, :headers, [])
    _token = OtelNats.extract_and_attach(headers)

    Tracer.with_span "UserSvc.NatsConsumer.convert.url.to_pdf" do
      req = Mcsv.V3.ImageConversionRequest.decode(body)

      # Inject trace context for outgoing message
      trace_headers = OtelNats.inject()
      :ok = forward_url_to_image_svc(req, trace_headers)
      :ok
    end
  end

  defp store_image(request) do
    # Extract data from oneof source field
    {:image_data, data} = request.source

    %{
      input_format: format,
      user_email: user_email,
      user_id: user_id,
      job_id: job_id
    } = request

    case ImageStorage.store(data, job_id, user_id, user_email, format) do
      {:ok, {_job_id, _presigned_url, _size}} ->
        :ok

      {:error, reason} ->
        OpenTelemetry.Tracer.set_status(:error, "Storage failed")
        {:error, reason}
    end
  end

  defp forward_binary_to_image_svc(req, trace_headers) do
    # Request already has source: {:image_data, binary} - just encode as-is
    img = Mcsv.V3.ImageConversionRequest.encode(req)

    :ok = Gnat.pub(:gnat, "image.convert.binary.to_pdf", img, headers: trace_headers)
    Logger.info("[NatsConsumer] Image conversion request from binary sent to Image")
    :ok
  end

  defp forward_url_to_image_svc(req, trace_headers) do
    # Request already has source: {:s3_ref, %{...}} - just encode as-is
    img = Mcsv.V3.ImageConversionRequest.encode(req)

    Logger.info("[NatsConsumer] Image conversion request from key sent to Image")
    :ok = Gnat.pub(:gnat, "image.convert.url.to_pdf", img, headers: trace_headers)
  end
end
