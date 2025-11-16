defmodule ImageSvc.NatsConsumer do
  require Logger
  require OpenTelemetry.Tracer, as: Tracer

  def handle_message(%{topic: "image.convert.to_pdf", body: body} = message) do
    # Extract trace context from incoming NATS message and attach it
    headers = Map.get(message, :headers, [])
    _token = OtelNats.extract_and_attach(headers)

    Tracer.with_span "ImageSvc.NatsConsumer.convert.to_pdf" do
      %Mcsv.V2.ImageConversionRequest{} =
        req = Mcsv.V2.ImageConversionRequest.decode(body)

      with {:ok, image_binary} <- fetch_image(req.image_url) do
        ctx = OpenTelemetry.Ctx.get_current()
        # save ctx before spawning new process

        info_task =
          Task.async(fn ->
            # inject trace context into new process
            OpenTelemetry.Ctx.attach(ctx)
            ImageMagick.get_image_info(image_binary)
          end)

        conversion_task =
          Task.async(fn ->
            # inject trace context into new process
            OpenTelemetry.Ctx.attach(ctx)
            perform_conversion(req, image_binary)
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
                # storage_id is the S3 key
                key,
                # original_storage_id from the request
                req.storage_id,
                # user_email from the request
                req.user_email
              )

            # Inject trace context into outgoing message
            trace_headers = OtelNats.inject()
            :ok = Gnat.pub(:gnat, "user.image.converted", response_binary, headers: trace_headers)

          [{:error, reason}, _] ->
            Logger.error(
              "[Image][ConversionController] get_image_info failed: #{inspect(reason)}"
            )

            OpenTelemetry.Tracer.set_status(:error, "Image info failed")
            {:error, :conversion_failed}
            {:error, :image_info_failed}

          [_, {:error, reason}] ->
            Logger.error(
              "[Image][ConversionController] perform_conversion failed: #{inspect(reason)}"
            )

            OpenTelemetry.Tracer.set_status(:error, "Conversion failed")
            {:error, :conversion_failed}
            {:error, :conversion_failed}

          [{:error, info_reason}, {:error, conv_reason}] ->
            Logger.error(
              "[Image][ConversionController] Both tasks failed - info: #{inspect(info_reason)}, conversion: #{inspect(conv_reason)}"
            )

            OpenTelemetry.Tracer.set_status(:error, "Conversion & image info failed")
            {:error, :conversion_failed}
            {:error, :all_failed}
        end
      else
        {:error, reason} ->
          Logger.error("[Image][ConversionController] fetch_image failed: #{inspect(reason)}")
          OpenTelemetry.Tracer.set_status(:error, "Fetch failed")
          {:error, :conversion_failed}
          {:error, :fetch_failed}
      end
    end
  end

  def build_ack_response(
        image_info,
        output_size,
        pdf_url,
        storage_id,
        original_storage_id,
        user_email
      ) do
    %Mcsv.V2.ImageConversionResponse{
      success: true,
      message: "Conversion completed",
      input_size: image_info.size,
      output_size: output_size,
      width: image_info.width,
      height: image_info.height,
      storage_id: storage_id,
      original_storage_id: original_storage_id,
      pdf_url: pdf_url,
      user_email: user_email
    }
    |> Mcsv.V2.ImageConversionResponse.encode()
  end

  defp fetch_image(image_url) do
    Tracer.with_span "image.fetch", %{
      "image.url" => image_url
    } do
      Logger.info("[Image][ConversionController] Fetching image: #{image_url}")

      case Req.get(image_url) do
        {:ok, %{status: 200, body: image_binary}} ->
          Logger.info("[Image][ConversionController] Fetched #{byte_size(image_binary)} bytes")
          OpenTelemetry.Tracer.set_attributes(%{"image.size_bytes" => byte_size(image_binary)})
          {:ok, image_binary}

        {:ok, %{status: status}} ->
          Logger.error("[Image][ConversionController] Failed to fetch image: HTTP #{status}")
          OpenTelemetry.Tracer.set_status(:error, "HTTP #{status}")
          {:error, :fetch_failed, status}

        {:error, reason} ->
          Logger.error("[Image][ConversionController] Failed to fetch image: #{inspect(reason)}")
          OpenTelemetry.Tracer.set_status(:error, inspect(reason))
          {:error, :fetch_failed, reason}
      end
    end
  end

  defp build_s3_url(bucket, key) do
    # Get MinIO endpoint from config
    s3_endpoint = Application.get_env(:ex_aws, :s3)[:host] || "localhost"
    s3_port = Application.get_env(:ex_aws, :s3)[:port] || 9000
    s3_scheme = Application.get_env(:ex_aws, :s3)[:scheme] || "http://"

    "#{s3_scheme}#{s3_endpoint}:#{s3_port}/#{bucket}/#{key}"
  end

  defp perform_conversion(request, image_binary) do
    OpenTelemetry.Tracer.with_span "image.convert_to_pdf", %{
      "input_format" => request.input_format,
      "pdf_quality" => request.pdf_quality,
      "input_size_bytes" => byte_size(image_binary)
    } do
      opts =
        ImageSvc.ConversionOptions.build(
          request.input_format,
          request.pdf_quality,
          request.strip_metadata,
          request.max_width,
          request.max_height
        )

      with {:ok, pdf_binary} <-
             ImageSvc.ParallelConverterStream.convert_to_pdf(image_binary, opts),
           {:ok, %{bucket: bucket, key: key, size: size}} <-
             upload_binary_to_s3(pdf_binary, bucket()) do
        # Return data to job_svc.
        Logger.info("[Image][ConversionController] Conversion complete: #{bucket}/#{key}")
        OpenTelemetry.Tracer.set_attributes(%{"output_size_bytes" => byte_size(pdf_binary)})
        {:ok, bucket, key, size}
      else
        _ ->
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
