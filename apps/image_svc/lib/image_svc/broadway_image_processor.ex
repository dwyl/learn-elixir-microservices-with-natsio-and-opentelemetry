defmodule ImageSvc.BroadwayImageProcessor do
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
          # Pull up to 10 messages per batch
          # Check for new messages every 100ms
          connection_name: :gnat,
          stream_name: "IMAGES",
          consumer_name: "pdf_processor",
          max_number_of_messages: 10,
          receive_interval: 100
        },
        concurrency: 2
      ],
      processors: [
        default: [concurrency: 4]
      ]
    )
  end

  @impl true
  def handle_message(_processor_name, message, _context) do
    Logger.info("[Broadway] Processing message")

    # Extract trace context from message headers
    headers = message.metadata[:headers] || []
    _token = OtelNats.extract_and_attach(headers)

    # Process the conversion within a span
    result =
      Tracer.with_span "Broadway.ImageProcessor.handle_message" do
        perform_conversion(message.data)
      end

    case result do
      :ok ->
        Logger.info("[Broadway] Conversion succeeded")
        # Return message unchanged - Broadway will ACK automatically
        message

      {:error, reason} ->
        Logger.error("[Broadway] Conversion failed: #{inspect(reason)}")
        # Configure to NACK on failure - message will be redelivered
        Message.failed(message, reason)
    end
  end

  defp perform_conversion(binary_body) do
    %Mcsv.V3.ImageConversionRequest{} = req = Mcsv.V3.ImageConversionRequest.decode(binary_body)

    ctx = OpenTelemetry.Ctx.get_current()

    info_task =
      Task.async(fn ->
        OpenTelemetry.Ctx.attach(ctx)
        ImageMagick.get_image_info(req.image_data)
      end)

    conversion_task =
      Task.async(fn ->
        OpenTelemetry.Ctx.attach(ctx)
        convert_to_pdf(req)
      end)

    case Task.await_many([info_task, conversion_task], 120_000) do
      [{:ok, image_info}, {:ok, bucket, key, output_size}] ->
        pdf_url = build_s3_url(bucket, key)

        response_binary =
          build_ack_response(image_info, output_size, pdf_url, req.job_id, req.user_email)

        # Use inject_with_link to include span_id for linking the return path
        trace_headers = OtelNats.inject_with_link()
        :ok = Gnat.pub(:gnat, "user.image.converted", response_binary, headers: trace_headers)
        :ok

      [{:error, reason}, _] ->
        Logger.error("[Image] get_image_info failed: #{inspect(reason)}")
        OpenTelemetry.Tracer.set_status(:error, "Image info failed")
        {:error, :image_info_failed}

      [_, {:error, reason}] ->
        Logger.error("[Image] perform_conversion failed: #{inspect(reason)}")
        OpenTelemetry.Tracer.set_status(:error, "Conversion failed")
        {:error, :conversion_failed}

      [{:error, info_reason}, {:error, conv_reason}] ->
        Logger.error(
          "[Image] Both tasks failed - info: #{inspect(info_reason)}, conversion: #{inspect(conv_reason)}"
        )

        OpenTelemetry.Tracer.set_status(:error, "Conversion & image info failed")
        {:error, :all_failed}
    end
  end

  defp convert_to_pdf(req) do
    OpenTelemetry.Tracer.with_span "image.convert_to_pdf", %{
      "input_format" => req.input_format,
      "pdf_quality" => req.pdf_quality,
      "input_size_bytes" => byte_size(req.image_data)
    } do
      opts =
        ImageSvc.ConversionOptions.build(
          req.input_format,
          req.pdf_quality,
          req.strip_metadata,
          req.max_width,
          req.max_height
        )

      with {:ok, pdf_binary} <-
             ImageSvc.ParallelConverterStream.convert_to_pdf(req.image_data, opts),
           {:ok, {bucket, key, size}} <-
             upload_binary_to_s3(pdf_binary, bucket()) do
        Logger.info("[Image] Conversion complete: #{bucket}/#{key}")
        OpenTelemetry.Tracer.set_attributes(%{"output_size_bytes" => byte_size(pdf_binary)})
        {:ok, bucket, key, size}
      else
        {:error, reason} ->
          Logger.error("[Image] Conversion to PDF failed: #{inspect(reason)}")
          OpenTelemetry.Tracer.set_status(:error, "Conversion failed")
          {:error, :conversion_failed}
      end
    end
  end

  defp bucket do
    Application.get_env(:image_svc, :image_bucket, "msvc-images")
  end

  defp upload_binary_to_s3(pdf_binary, bucket) do
    case Storage.store(pdf_binary, bucket, format: "pdf") do
      {:ok, result} ->
        {:ok, {result.bucket, result.key, result.size}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp build_s3_url(bucket, key) do
    s3_endpoint = Application.get_env(:ex_aws, :s3)[:host] || "localhost"
    s3_port = Application.get_env(:ex_aws, :s3)[:port] || 9000
    s3_scheme = Application.get_env(:ex_aws, :s3)[:scheme] || "http://"

    "#{s3_scheme}#{s3_endpoint}:#{s3_port}/#{bucket}/#{key}"
  end

  defp build_ack_response(image_info, output_size, pdf_url, job_id, user_email) do
    %Mcsv.V3.ImageConversionResponse{
      success: true,
      message: "Conversion completed",
      input_size: image_info.size,
      output_size: output_size,
      width: image_info.width,
      height: image_info.height,
      job_id: job_id,
      pdf_url: pdf_url,
      user_email: user_email
    }
    |> Mcsv.V3.ImageConversionResponse.encode()
  end
end
