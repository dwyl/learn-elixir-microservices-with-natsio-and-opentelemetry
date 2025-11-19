defmodule Broadway.Images.BinaryToPdf do
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
          stream_name: "IMAGES",
          consumer_name: "binary_to_pdf",
          # Fetch more messages per batch for better throughput
          max_number_of_messages: 50,
          # Check for messages more frequently (10ms vs 100ms) for lower latency
          receive_interval: 10
        },
        concurrency: 2
      ],
      processors: [
        # Increase processor concurrency for parallel image conversions
        default: [concurrency: 8]
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
    image_bucket = S3Things.bucket_image()

    case convert_to_pdf(req, image_bucket) do
      {:ok, bucket, key, output_size} ->
        pdf_url = ReqS3Storage.generate_presigned_url(bucket, key, S3Things.s3_opts())

        # Extract binary from oneof source field
        {:image_data, binary} = req.source

        response_binary =
          build_ack_response(
            byte_size(binary),
            output_size,
            pdf_url,
            req.job_id,
            req.user_email
          )

        # Use inject_with_link to include span_id for linking the return path
        trace_headers = OtelNats.inject_with_link()
        :ok = Gnat.pub(:gnat, "user.image.converted", response_binary, headers: trace_headers)
        :ok

      {:error, reason} ->
        Logger.error("[Broadway] Conversion failed: #{inspect(reason)}")
        OpenTelemetry.Tracer.set_status(:error, "Conversion failed")
        {:error, reason}
    end
  end

  defp convert_to_pdf(req, image_bucket) do
    # Broadway BinaryToPdf ONLY handles {:image_data, ...}
    {:image_data, binary} = req.source

    OpenTelemetry.Tracer.with_span "image.convert_to_pdf", %{
      "input_format" => req.input_format,
      "pdf_quality" => req.pdf_quality,
      "input_size_bytes" => byte_size(binary)
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
             IM.Converter.convert_to_pdf(binary, opts),
           {:ok, {key, size}} <-
             upload_binary_to_s3(pdf_binary, image_bucket, req.job_id) do
        Logger.info("[Image] Conversion complete: #{image_bucket}/#{key}")
        OpenTelemetry.Tracer.set_attributes(%{"output_size_bytes" => byte_size(pdf_binary)})
        {:ok, image_bucket, key, size}
      else
        {:error, reason} ->
          Logger.error("[Image] Conversion to PDF failed: #{inspect(reason)}")
          OpenTelemetry.Tracer.set_status(:error, "Conversion failed")
          {:error, :conversion_failed}
      end
    end
  end

  defp upload_binary_to_s3(pdf_binary, bucket, job_id) do
    case ReqS3Storage.store(pdf_binary, bucket, job_id, "application/pdf", S3Things.s3_opts()) do
      {:ok, %{bucket: bucket, key: key, size: size, presigned_url: _presigned_url}} ->
        Logger.info("[Broadway] Uploaded PDF to #{bucket}/#{key} (#{size} bytes)")
        {:ok, {key, size}}

      {:error, reason} ->
        Logger.error("[Broadway] Failed to upload PDF: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp build_ack_response(input_size, output_size, pdf_url, job_id, user_email) do
    %Mcsv.V3.ImageConversionResponse{
      success: true,
      message: "Conversion completed",
      input_size: input_size,
      output_size: output_size,
      width: 0,
      height: 0,
      job_id: job_id,
      pdf_url: pdf_url,
      user_email: user_email
    }
    |> Mcsv.V3.ImageConversionResponse.encode()
  end
end
