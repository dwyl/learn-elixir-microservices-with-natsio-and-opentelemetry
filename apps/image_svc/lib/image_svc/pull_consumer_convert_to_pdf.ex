defmodule PullConsumer.ConvertToPdf do
  use Jetstream.PullConsumer
  require OpenTelemetry.Tracer, as: Tracer
  require Logger

  def start_link([]) do
    Jetstream.PullConsumer.start_link(__MODULE__, [])
  end

  @impl true
  def init([]) do
    {:ok, nil, connection_name: :gnat, stream_name: "IMAGES", consumer_name: "pdf_processor"}
  end

  @impl true
  def handle_message(message, state) do
    Logger.info("[PullConsumer] Received message, starting conversion")
    headers = message.headers || []
    _token = OtelNats.extract_and_attach(headers)

    result =
      Tracer.with_span "PullConsumer.ConvertToPdf.handle_message" do
        perform_conversion(message)
      end

    # Manually ACK/NACK before returning - the library's {:ack, state} doesn't work
    case result do
      :ok ->
        Logger.info("[PullConsumer] Conversion succeeded, sending manual ACK")
        if message.reply_to do
          :ok = Gnat.pub(:gnat, message.reply_to, "+ACK")
          Logger.info("[PullConsumer] ACK sent to #{message.reply_to}")
        end

      {:error, reason} ->
        Logger.error("[PullConsumer] Conversion failed: #{inspect(reason)}, sending NACK")
        if message.reply_to do
          :ok = Gnat.pub(:gnat, message.reply_to, "-NAK")
          Logger.info("[PullConsumer] NACK sent to #{message.reply_to}")
        end

      other ->
        Logger.error("[PullConsumer] Unexpected result: #{inspect(other)}, sending NACK")
        if message.reply_to do
          :ok = Gnat.pub(:gnat, message.reply_to, "-NAK")
        end
    end

    # Always return {:ack, state} to satisfy the behavior, even though we handled it manually
    {:ack, state}
  end

  def perform_conversion(message) do
    %Mcsv.V3.ImageConversionRequest{} =
      req =
      Mcsv.V3.ImageConversionRequest.decode(message.body)

    ctx = OpenTelemetry.Ctx.get_current()
    # save ctx before spawning new process

    info_task =
      Task.async(fn ->
        # inject trace context into new process
        OpenTelemetry.Ctx.attach(ctx)
        ImageMagick.get_image_info(req.image_data)
      end)

    conversion_task =
      Task.async(fn ->
        # inject trace context into new process
        OpenTelemetry.Ctx.attach(ctx)
        convert_to_pdf(req)
      end)

    case Task.await_many([info_task, conversion_task], 120_000) do
      [{:ok, image_info}, {:ok, bucket, key, output_size}] ->
        # Build MinIO URL for the PDF
        pdf_url = build_s3_url(bucket, key)

        response_binary =
          build_ack_response(
            image_info,
            output_size,
            pdf_url,
            req.job_id,
            req.user_email
          )

        # Inject trace context into outgoing message
        trace_headers = OtelNats.inject()
        :ok = Gnat.pub(:gnat, "user.image.converted", response_binary, headers: trace_headers)
        :ok

      [{:error, reason}, _] ->
        Logger.error("[Image][ConversionController] get_image_info failed: #{inspect(reason)}")
        OpenTelemetry.Tracer.set_status(:error, "Image info failed")
        {:error, :image_info_failed}

      [_, {:error, reason}] ->
        Logger.error(
          "[Image][ConversionController] perform_conversion failed: #{inspect(reason)}"
        )

        OpenTelemetry.Tracer.set_status(:error, "Conversion failed")
        {:error, :conversion_failed}

      [{:error, info_reason}, {:error, conv_reason}] ->
        Logger.error(
          "[Image][ConversionController] Both tasks failed - info: #{inspect(info_reason)}, conversion: #{inspect(conv_reason)}"
        )

        OpenTelemetry.Tracer.set_status(:error, "Conversion & image info failed")
        {:error, :all_failed}
    end
  end

  def build_ack_response(
        image_info,
        output_size,
        pdf_url,
        job_id,
        user_email
      ) do
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

  defp build_s3_url(bucket, key) do
    # Get MinIO endpoint from config
    s3_endpoint = Application.get_env(:ex_aws, :s3)[:host] || "localhost"
    s3_port = Application.get_env(:ex_aws, :s3)[:port] || 9000
    s3_scheme = Application.get_env(:ex_aws, :s3)[:scheme] || "http://"

    "#{s3_scheme}#{s3_endpoint}:#{s3_port}/#{bucket}/#{key}"
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
           {:ok, %{bucket: bucket, key: key, size: size}} <-
             upload_binary_to_s3(pdf_binary, bucket()) do
        # Return data to job_svc.
        Logger.info("[Image][ConversionController] Conversion complete: #{bucket}/#{key}")
        OpenTelemetry.Tracer.set_attributes(%{"output_size_bytes" => byte_size(pdf_binary)})
        {:ok, bucket, key, size}
      else
        {:error, reason} ->
          Logger.error(
            "[Image][ConversionController] Conversion to PDF failed: #{inspect(reason)}"
          )

          OpenTelemetry.Tracer.set_status(:error, "Conversion failed")
          {:error, :conversion_failed}
      end
    end
  end

  defp bucket do
    Application.get_env(:image_svc, :image_bucket, "msvc-images")
  end

  defp upload_binary_to_s3(pdf_binary, bucket) do
    key = generate_storage_id()

    OpenTelemetry.Tracer.with_span "storage.s3.put_object", %{
      "s3.bucket" => bucket,
      "s3.key" => key,
      "content.size" => byte_size(pdf_binary),
      "content.type" => "application/pdf"
    } do
      # Upload to S3
      ExAws.S3.put_object(bucket, key, pdf_binary, content_type: "application/pdf")
      |> ExAws.request()
      |> case do
        {:ok, _} ->
          {:ok, %{bucket: bucket, key: key, size: byte_size(pdf_binary)}}

        {:error, reason} ->
          OpenTelemetry.Tracer.set_status(:error, inspect(reason))
          {:error, reason}
      end
    end
  end

  defp generate_storage_id() do
    timestamp = System.system_time(:microsecond)
    random = :crypto.strong_rand_bytes(8) |> Base.url_encode64(padding: false)
    "#{timestamp}_#{random}.pdf"
  end
end
