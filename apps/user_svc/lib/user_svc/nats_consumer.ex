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

    Tracer.with_span "UserSvc.NatsConsumer.email.create" do
      Logger.info("[NatsConsumer] Received message on email.create")

      # Inject trace context into outgoing message
      trace_headers = OtelNats.inject()
      :ok = Gnat.pub(:gnat, "email.send", body, headers: trace_headers)
    end
  end

  def handle_message(%{topic: "user.email.delivered"} = message) do
    Logger.info("[NatsConsumer] Raw message: #{inspect(message)}")

    body = Map.get(message, :body)
    headers = Map.get(message, :headers, [])

    Logger.info("[NatsConsumer] Headers: #{inspect(headers)}")

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

    Tracer.with_span "UserSvc.NatsConsumer.image.converted" do
      Logger.info("[NatsConsumer] Image converted")

      # Inject trace context into outgoing message
      trace_headers = OtelNats.inject()
      :ok = Gnat.pub(:gnat, "client.image.converted", body, headers: trace_headers)
    end
  end

  def handle_message(%{topic: "user.convert.to_pdf", body: body} = message) do
    # Extract trace context from incoming NATS message and attach it
    headers = Map.get(message, :headers, [])
    _token = OtelNats.extract_and_attach(headers)

    Tracer.with_span "UserSvc.NatsConsumer.convert.to_pdf" do
      req = Mcsv.V2.ImageConversionRequest.decode(body)

      with {:ok, storage_id} <- store_image(req) do
        # Inject trace context for outgoing message
        trace_headers = OtelNats.inject()
        :ok = forward_to_job_svc(req, storage_id, trace_headers)
        Logger.info("[NatsConsumer] Image conversion request sent to Image")
      else
        {:error, reason} ->
          Logger.error("[NatsConsumer] Error processing image conversion: #{inspect(reason)}")
          OpenTelemetry.Tracer.set_status(:error, "Processing failed")
          {:error, :processing_failed}
      end
    end
  end

  defp store_image(request) do
    format = if request.input_format == "", do: "png", else: request.input_format

    case ImageStorage.store(request.image_data, request.user_id, format) do
      {:ok, storage_id} ->
        Logger.info("[User][ConvertImageController] Stored image as #{storage_id}")
        {:ok, storage_id}

      {:error, reason} ->
        OpenTelemetry.Tracer.set_status(:error, "Storage failed")
        {:error, reason}
    end
  end

  defp user_svc_base_url do
    Application.get_env(:user_svc, :user_svc_base_url)
  end

  defp user_svc_image_loader do
    Application.get_env(:user_svc, :user_svc_endpoints)[:image_loader]
  end

  defp build_presigned_url(storage_id) do
    "#{user_svc_base_url()}#{user_svc_image_loader()}/#{storage_id}"
  end

  defp forward_to_job_svc(request, storage_id, trace_headers) do
    # Build image URL for other services to fetch
    image_url = build_presigned_url(storage_id)

    Logger.info("[User][ConvertImageController] Image URL: #{image_url}")

    img =
      %Mcsv.V2.ImageConversionRequest{
        user_id: request.user_id,
        user_email: request.user_email,
        image_url: image_url,
        input_format: request.input_format,
        pdf_quality: request.pdf_quality,
        strip_metadata: request.strip_metadata,
        max_width: request.max_width,
        max_height: request.max_height,
        storage_id: storage_id
      }
      |> Mcsv.V2.ImageConversionRequest.encode()

    :ok = Gnat.pub(:gnat, "image.convert.to_pdf", img, headers: trace_headers)
  end
end
