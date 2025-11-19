defmodule Image do
  @moduledoc """
  Client for testing PNG to PDF conversion

  ## Examples

      iex> Image.convert_png("priv/test.png", "user@example.com")
      :ok
      iex> 1..1000 |> Enum.to_list()
          |> Task.async_stream(
              fn i ->
                Image.convert_png("priv/test.png", "user@example.com")
                end,
              max_concurrency: 20,
              ordered: false)
          |> Stream.run()

  """

  require Logger
  require OpenTelemetry.Tracer, as: Tracer

  @doc """
  Convert a PNG binary to PDF by sending a NATS message to the User service. Accepts optional parameters: [:input_format, :pdf_quality, :max_width, :max_height, :strip_metadata]

  ## Examples

      iex> Image.convert_png("priv/large.png", "user@example.com",
        quality: "high",
        max_width: 2000
      )
  """
  def convert_bin(png_binary, user_email, opts \\ []) do
    Tracer.with_span "image_client.convert_png", %{kind: :client} do
      Tracer.set_attribute("user.email", user_email)
      png_size = byte_size(png_binary)
      Tracer.set_attribute("image.size_bytes", png_size)

      case ExImageInfo.info(png_binary) do
        {mimetype, width, height, _} ->
          Logger.info("Sending Image of type #{mimetype} to User service...: #{png_size}")

          job_id = generate_job_id()

          Tracer.set_attribute("image.width", width)
          Tracer.set_attribute("image.height", height)
          Tracer.set_attribute("image.format", mimetype)
          Tracer.set_attribute("image.job_id", job_id)
          trace_headers = OtelNats.inject()

          req =
            build_proto_request(
              :binary,
              png_binary,
              user_email,
              mimetype,
              job_id,
              opts
            )

          Gnat.pub(
            :gnat,
            "user.convert.binary.to_pdf",
            req,
            headers: trace_headers
          )

        nil ->
          Logger.error("Failed to get image info")
          Tracer.set_status(:error, "Failed to get image info")
          raise "Invalid image"
      end
    end
  end

  @doc """
  Convert an image from S3 key (filename) to PDF using streaming.

  Pass the S3 object key directly (e.g., "large_test_123.png").
  The bucket is configured in image_svc.

  ## Examples

      iex> Image.convert_from_s3("large_test_123.png", "user@example.com",
        input_format: "png",
        quality: "high"
      )
  """
  def convert_from_s3(key, user_email, opts \\ []) do
    Tracer.with_span "image_client.convert_from_s3", %{kind: :client} do
      Tracer.set_attribute("user.email", user_email)
      Tracer.set_attribute("s3.key", key)
      job_id = generate_job_id()
      Tracer.set_attribute("image.job_id", job_id)

      Logger.info("Sending S3 key to User service: #{key}")

      req =
        build_proto_request(
          :s3_key,
          key,
          user_email,
          nil,
          job_id,
          opts
        )

      trace_headers = OtelNats.inject()
      :ok = Gnat.pub(:gnat, "user.convert.url.to_pdf", req, headers: trace_headers)
    end
  end

  defp build_proto_request(kind, source, user_email, mimetype, job_id, opts)
       when kind in [:binary, :s3_key] do
    case kind do
      :binary ->
        %Mcsv.V3.ImageConversionRequest{
          # oneof source - inline binary
          source: {:image_data, source},
          user_email: user_email,
          user_id: "test-user-#{:rand.uniform(1000)}",
          input_format: mimetype,
          pdf_quality: Keyword.get(opts, :quality, "high"),
          strip_metadata: Keyword.get(opts, :strip_metadata, true),
          max_width: Keyword.get(opts, :max_width, 1_000),
          max_height: Keyword.get(opts, :max_height, 1_000),
          job_id: job_id
        }

      :s3_key ->
        # Build proper S3Reference structure
        %Mcsv.V3.ImageConversionRequest{
          # oneof source - S3 reference with bucket and key
          source:
            {:s3_ref,
             %Mcsv.V3.S3Reference{
               bucket: image_bucket(),
               key: source
             }},
          user_email: user_email,
          user_id: "test-user-#{:rand.uniform(1000)}",
          # input_format must be provided in opts for S3 sources
          input_format: Keyword.get(opts, :input_format, "png"),
          pdf_quality: Keyword.get(opts, :quality, "high"),
          strip_metadata: Keyword.get(opts, :strip_metadata, true),
          max_width: Keyword.get(opts, :max_width, 1_000),
          max_height: Keyword.get(opts, :max_height, 1_000),
          job_id: job_id
        }
    end
    |> Mcsv.V3.ImageConversionRequest.encode()
  end

  defp generate_job_id do
    timestamp = System.system_time(:microsecond)
    random = :crypto.strong_rand_bytes(8) |> Base.url_encode64(padding: false)
    "#{timestamp}_#{random}"
  end

  defp image_bucket do
    Application.get_env(:client_svc, :s3)
    |> Keyword.get(:image_bucket, "msvc-images")
  end
end
