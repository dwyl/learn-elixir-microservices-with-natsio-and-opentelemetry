defmodule Broadway.Images.UrlToPdf do
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
          # Fetch more messages per batch for better throughput
          # Check for messages more frequently (10ms vs 100ms) for lower latency
          connection_name: :gnat,
          stream_name: "IMAGES",
          consumer_name: "url_to_pdf",
          max_number_of_messages: 50,
          receive_interval: 10
        },
        concurrency: 2
      ],
      processors: [
        # Increase processor concurrency for parallel S3 streaming conversions
        im: [concurrency: 8]
      ]
    )
  end

  @impl true
  def handle_message(:im, msg, _ctx) do
    Logger.info("[Broadway] Processing URL/streaming message")

    # Extract trace context from message headers
    headers = msg.metadata[:headers] || []
    _token = OtelNats.extract_and_attach(headers)

    %Broadway.Message{data: data} = msg
    # Process the conversion within a span
    result =
      Tracer.with_span "Broadway.Images.UrlToPdf.handle_message" do
        perform_conversion(data)
      end

    case result do
      :ok ->
        Logger.info("[Broadway] Streaming conversion succeeded")
        # Return message unchanged - Broadway will ACK automatically
        msg

      {:error, reason} ->
        Logger.error("[Broadway] Streaming conversion failed: #{inspect(reason)}")
        # Configure to NACK on failure - message will be redelivered
        Message.failed(msg, reason)
    end
  end

  defp perform_conversion(binary_body) do
    %Mcsv.V3.ImageConversionRequest{} = req = Mcsv.V3.ImageConversionRequest.decode(binary_body)

    image_bucket = S3Things.bucket_image()

    case convert_to_pdf(req, image_bucket) do
      {:ok, bucket, key, output_size} ->
        pdf_url = ReqS3Storage.generate_presigned_url(bucket, key, S3Things.s3_opts())

        response_binary =
          build_ack_response(
            0,
            # Size unknown for S3 source
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
        Logger.error("[Broadway] Streaming conversion failed: #{inspect(reason)}")
        OpenTelemetry.Tracer.set_status(:error, "Streaming conversion failed")
        {:error, reason}
    end
  end

  defp convert_to_pdf(req, image_bucket) do
    # Broadway UrlToPdf handles {:s3_ref, ...} for S3 streaming
    {:s3_ref, %{bucket: ^image_bucket, key: key}} = req.source

    OpenTelemetry.Tracer.with_span "image.convert_to_pdf_from_s3", %{
      "input_format" => req.input_format,
      "pdf_quality" => req.pdf_quality,
      "s3.bucket" => image_bucket,
      "s3.key" => key,
      "conversion.method" => "s3_stream_to_s3"
    } do
      Logger.info("[Broadway] Converting from S3: #{image_bucket}/#{key}")
      convert_from_s3(req, image_bucket, key)
    end
  end

  defp convert_from_s3(req, bucket, key) do
    opts =
      ImageSvc.ConversionOptions.build(
        req.input_format,
        req.pdf_quality,
        req.strip_metadata,
        req.max_width,
        req.max_height
      )

    s3_opts = S3Things.s3_opts()

    # Stream from S3 -> ImageMagick, returns accumulated PDF binary
    with {:ok, pdf_binary} <-
           IM.Converter.convert_from_s3(
             bucket,
             key,
             Keyword.merge(opts, s3_opts: s3_opts)
           ),
         {:ok, upload_result} <-
           upload_binary_to_s3(pdf_binary, bucket, req.job_id, s3_opts) do
      Logger.info(
        "[Broadway] Conversion complete: #{upload_result.bucket}/#{upload_result.key} (#{upload_result.size}B)"
      )

      Logger.info("[Broadway] Spawning cleanup task to delete original image: #{bucket}/#{key}")

      task_result =
        Task.Supervisor.start_child(
          ImageService.TaskSupervisor,
          fn ->
            Logger.info("[Broadway.Cleanup] Task executing - deleting #{bucket}/#{key}")

            case ReqS3Storage.delete(bucket, key, s3_opts) do
              :ok ->
                Logger.info("[Broadway.Cleanup] Successfully deleted original image: #{bucket}/#{key}")

              {:error, reason} ->
                Logger.error(
                  "[Broadway.Cleanup] Failed to delete original image #{bucket}/#{key}: #{inspect(reason)}"
                )
            end
          end
        )

      Logger.info("[Broadway] Cleanup task spawn result: #{inspect(task_result)}")

      OpenTelemetry.Tracer.set_attributes(%{"output_size_bytes" => upload_result.size})
      {:ok, upload_result.bucket, upload_result.key, upload_result.size}
    else
      {:error, reason} ->
        Logger.error("[Broadway] Conversion failed: #{inspect(reason)}")
        OpenTelemetry.Tracer.set_status(:error, "Conversion failed")
        {:error, :conversion_failed}
    end
  end

  defp upload_binary_to_s3(pdf_binary, bucket, job_id, s3_opts) do
    Logger.info("[Broadway] Uploading PDF to #{bucket}/#{job_id} (#{byte_size(pdf_binary)}B)")

    case ReqS3Storage.store(pdf_binary, bucket, job_id, "application/pdf", s3_opts) do
      {:ok, result} ->
        Logger.info("[Broadway] Uploaded PDF to #{bucket}/#{result.key}")
        {:ok, result}

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
