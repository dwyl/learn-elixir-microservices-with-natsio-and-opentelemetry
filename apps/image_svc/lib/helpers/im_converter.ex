defmodule IM.Converter do
  @moduledoc """
  Convert images to PDF using ExCmd.stream! for streaming efficiency.

  This is an intermediate implementation that:
  - Uses ExCmd.stream! (vs ExCmd.Process in ParallelConverter)
  - Returns PDF binary (same interface as ParallelConverter)
  - Does NOT upload to MinIO yet (that's a later step)

  Key differences from ParallelConverter:
  - Streams data through ImageMagick instead of manual write/read
  - More memory efficient for large images
  - Simpler error handling (stream exceptions)
  """

  require Logger
  require OpenTelemetry.Tracer

  @doc """
  Convert image from S3 bucket to PDF, returning the complete PDF binary.

  This function streams data from S3 directly into ImageMagick's stdin and accumulates
  the PDF output into a binary. The accumulation is necessary because S3 multipart upload
  requires minimum 5MB chunks, which ImageMagick may not produce.

  Options:
  - :quality - "low" | "medium" | "high" | "lossless" (default: "medium")
  - :input_format - Image format (e.g., "png", "jpeg")
  - :threads - Number of ImageMagick threads (default: auto-detect)
  - :s3_opts - S3 configuration (required: object_storage_endpoint, access_key_id, secret_access_key)

  Returns {:ok, pdf_binary} or {:error, reason}
  """
  def convert_from_s3(bucket, key, opts \\ []) do
    quality = Keyword.get(opts, :quality, "medium")
    input_format = Keyword.get(opts, :input_format, "png")
    threads = Keyword.get(opts, :threads, System.schedulers_online())
    s3_opts = Keyword.fetch!(opts, :s3_opts)

    Logger.info(
      "[IM.Converter] S3->ImageMagick pipeline: #{bucket}/#{key} (format: #{input_format}, quality: #{quality})"
    )

    start_time = System.monotonic_time(:millisecond)

    # Build ImageMagick args
    args = Args.build_streaming_args(input_format, quality, threads)
    full_cmd = ["magick" | args]

    # Start ImageMagick process (current process owns all pipes)
    {:ok, %ExCmd.Process{} = proc} =
      ExCmd.Process.start_link(full_cmd)

    Logger.debug("[IM.Converter] Started ImageMagick: #{inspect(proc)}")

    # Build S3 request
    %Req.Request{} =
      req =
      ReqS3Storage.build_req(s3_opts)

    Logger.info("[IM.Converter] Starting S3 download")

    OpenTelemetry.Tracer.with_span "imagemagick.convert.s3_stream", %{
      "s3.bucket" => bucket,
      "s3.key" => key,
      "imagemagick.quality" => quality,
      "imagemagick.input_format" => input_format
    } do
      with {:ok, %Req.Response{status: 200}} <-
             Req.get(req,
               url: "s3://#{bucket}/#{key}",
               compressed: false,
               into: fn {:data, chunk}, {req, resp} ->
                 :ok = ExCmd.Process.write(proc, chunk)
                 {:cont, {req, resp}}
               end
             ),
           :ok <-
             ExCmd.Process.close_stdin(proc),
           {:ok, pdf_binary} <-
             build_pdf_binary(proc) do
        Logger.debug("[IM.Converter] S3 download complete, stdin closed")

        size = byte_size(pdf_binary)
        duration = System.monotonic_time(:millisecond) - start_time

        OpenTelemetry.Tracer.set_attributes(%{
          "imagemagick.output_size_bytes" => size,
          "imagemagick.duration_ms" => duration
        })

        :telemetry.execute(
          [:image_svc, :conversion, :complete],
          %{duration: duration, size_bytes: size},
          %{quality: quality, threads: threads, method: :s3_stream}
        )

        {:ok, pdf_binary}
      else
        {:ok, %{status: status}} ->
          Logger.error("[IM.Converter] S3 download failed: HTTP #{status}")

          OpenTelemetry.Tracer.set_status(
            :error,
            "HTTP S3 retrieve by key error: #{status}"
          )

          {:error, {:s3_download_failed, status}}

        {:error, reason} ->
          Logger.error("[IM.Converter] Streaming error: #{inspect(reason)}")

          OpenTelemetry.Tracer.set_status(
            :error,
            "[IM.Converter] error: #{inspect(reason)}"
          )

          {:error, reason}
      end
    end
  end

  defp build_pdf_binary(proc) do
    # Simple: collect all output into a list, then join
    collect_output(proc, [])
  end

  defp collect_output(proc, acc) do
    case ExCmd.Process.read(proc) do
      {:ok, data} when byte_size(data) > 0 ->
        collect_output(proc, [data | acc])

      :eof ->
        binary = acc |> Enum.reverse() |> IO.iodata_to_binary()
        ExCmd.Process.await_exit(proc)
        {:ok, binary}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Convert image binary to PDF using streaming ImageMagick.

  Options:
  - :quality - "low" | "medium" | "high" | "lossless" (default: "medium")
  - :threads - Number of ImageMagick threads (default: auto-detect)

  Returns {:ok, pdf_binary} or {:error, reason}
  """
  def convert_to_pdf(image_binary, opts \\ []) when is_binary(image_binary) do
    quality = Keyword.get(opts, :quality, "medium")
    input_format = Keyword.get(opts, :input_format, "png")
    threads = Keyword.get(opts, :threads, System.schedulers_online())

    Logger.info(
      "[IM.Converter] Converting #{byte_size(image_binary)} bytes (format: #{input_format}, quality: #{quality}, threads: #{threads})"
    )

    start_time = System.monotonic_time(:millisecond)

    # Build ImageMagick args for stdin -> stdout conversion
    args = Args.build_streaming_args(input_format, quality, threads)

    # Log the full command for debugging
    full_cmd = ["magick" | args]
    Logger.info("[IM.Converter] Running: #{Enum.join(full_cmd, " ")}")

    OpenTelemetry.Tracer.with_span "imagemagick.convert", %{
      "imagemagick.input_format" => input_format,
      "imagemagick.quality" => quality,
      "imagemagick.threads" => threads,
      "imagemagick.input_size_bytes" => byte_size(image_binary)
    } do
      try do
        # Stream through ImageMagick
        pdf_binary =
          ExCmd.stream!(full_cmd, input: image_binary)
          |> Enum.reduce([], fn chunk, acc ->
            [chunk | acc]
          end)
          |> Enum.reverse()
          |> IO.iodata_to_binary()

        duration = System.monotonic_time(:millisecond) - start_time

        Logger.info("[IM.Converter] Success (#{duration}ms): #{byte_size(pdf_binary)} bytes")

        # Set OpenTelemetry attributes for output
        OpenTelemetry.Tracer.set_attributes(%{
          "imagemagick.output_size_bytes" => byte_size(pdf_binary),
          "imagemagick.duration_ms" => duration
        })

        # Emit telemetry for metrics
        :telemetry.execute(
          [:image_svc, :conversion, :complete],
          %{duration: duration, size_bytes: byte_size(pdf_binary)},
          %{quality: quality, threads: threads, method: :stream}
        )

        {:ok, pdf_binary}
      rescue
        e in ExCmd.Stream.AbnormalExit ->
          Logger.error(
            "[IM.Converter] ImageMagick failed with exit code #{e.exit_status}: #{Exception.message(e)}"
          )

          Logger.error("[IM.Converter] Command was: #{Enum.join(full_cmd, " ")}")

          OpenTelemetry.Tracer.set_status(
            :error,
            "ImageMagick exit #{e.exit_status}: #{Exception.message(e)}"
          )

          {:error, {:conversion_failed, e.exit_status, Exception.message(e)}}

        e ->
          Logger.error("[IM.Converter] Unexpected error: #{Exception.message(e)}")
          Logger.error("[IM.Converter] Error: #{inspect(e)}")

          OpenTelemetry.Tracer.set_status(:error, Exception.message(e))

          {:error, {:unexpected_error, Exception.message(e)}}
      end
    end
  end
end
