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

    # Decode response to log success/failure details
    %Mcsv.V3.ImageConversionResponse{} = response = Mcsv.V3.ImageConversionResponse.decode(body)

    # Create span with link to the Image service's conversion span
    span_opts = if link, do: %{links: [link]}, else: %{}

    Tracer.with_span "UserSvc.NatsConsumer.image.converted", span_opts do
      if response.success do
        Logger.info("[NatsConsumer] ✅ Image conversion succeeded (job_id: #{response.job_id}, size: #{response.output_size}B)")
      else
        Logger.error("[NatsConsumer] ❌ Image conversion failed (job_id: #{response.job_id}, error: #{response.message})")
        OpenTelemetry.Tracer.set_status(:error, "Image conversion failed: #{response.message}")
      end

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

      # Validate S3 object exists before forwarding to image service
      case validate_s3_source(req) do
        :ok ->
          # Inject trace context for outgoing message
          trace_headers = OtelNats.inject()
          :ok = forward_url_to_image_svc(req, trace_headers)
          :ok

        {:error, reason} ->
          Logger.error(
            "[NatsConsumer] S3 validation failed for job_id #{req.job_id}: #{inspect(reason)}"
          )

          OpenTelemetry.Tracer.set_status(:error, "S3 source validation failed")

          # Send immediate failure response back to client
          send_validation_failure_response(req, reason)
          {:error, reason}
      end
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
    Logger.info("[NatsConsumer] Forwarded binary image conversion request to image_svc (job_id: #{req.job_id})")
    :ok
  end

  defp forward_url_to_image_svc(req, trace_headers) do
    # Request already has source: {:s3_ref, %{...}} - just encode as-is
    img = Mcsv.V3.ImageConversionRequest.encode(req)

    :ok = Gnat.pub(:gnat, "image.convert.url.to_pdf", img, headers: trace_headers)
    Logger.info("[NatsConsumer] Forwarded S3 image conversion request to image_svc (job_id: #{req.job_id})")
    :ok
  end

  defp validate_s3_source(%{source: {:s3_ref, %{bucket: bucket, key: key}}} = _req) do
    s3_opts = ReqS3Storage.build_s3_opts(:user_svc)

    case ReqS3Storage.head_object(bucket, key, s3_opts) do
      {:ok, _metadata} ->
        Logger.debug("[NatsConsumer] S3 validation passed: #{bucket}/#{key} exists")
        :ok

      {:error, %{status: 404}} ->
        Logger.error("[NatsConsumer] S3 validation failed: #{bucket}/#{key} not found (404)")
        {:error, :s3_object_not_found}

      {:error, reason} ->
        Logger.error("[NatsConsumer] S3 validation failed: #{bucket}/#{key} error: #{inspect(reason)}")
        {:error, :s3_validation_error}
    end
  end

  defp validate_s3_source(_req) do
    # Not an S3 source (binary data), no validation needed
    :ok
  end

  defp send_validation_failure_response(req, reason) do
    error_message =
      case reason do
        :s3_object_not_found -> "Source image not found in S3"
        :s3_validation_error -> "Failed to validate S3 source"
        other -> "Validation error: #{inspect(other)}"
      end

    response_binary =
      %Mcsv.V3.ImageConversionResponse{
        success: false,
        message: error_message,
        input_size: 0,
        output_size: 0,
        width: 0,
        height: 0,
        job_id: req.job_id,
        pdf_url: "",
        user_email: req.user_email
      }
      |> Mcsv.V3.ImageConversionResponse.encode()

    trace_headers = OtelNats.inject_with_link()
    :ok = Gnat.pub(:gnat, "client.image.converted", response_binary, headers: trace_headers)

    Logger.error("[NatsConsumer] Sent validation failure response for job_id #{req.job_id}")
  end
end
