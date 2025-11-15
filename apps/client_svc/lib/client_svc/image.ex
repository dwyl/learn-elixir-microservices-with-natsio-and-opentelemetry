defmodule Image do
  @moduledoc """
  Client for testing PNG to PDF conversion

  ## Examples

      iex> ImageClient.convert_png("priv/test.png", "user@example.com")

      iex> ImageClient.convert_png("priv/large.png", "user@example.com",
        quality: "high",
        max_width: 2000
      )

      iex> 1..1000 |> Enum.to_list()
          |> Task.async_stream(
              fn i ->
                ImageClient.convert_png("priv/test.png", "user@example.com")
                end,
              max_concurrency: 20,
              ordered: false)
          |> Stream.run()

  """

  require Logger
  require OpenTelemetry.Tracer, as: Tracer

  def convert_png(png_binary, user_email, opts \\ []) do
    Tracer.with_span "image_client.convert_png", %{kind: :client} do
      Tracer.set_attribute("user.email", user_email)
      png_size = byte_size(png_binary)
      Tracer.set_attribute("image.size_bytes", png_size)

      request =
        %Mcsv.V2.ImageConversionRequest{
          user_id: "test-user-#{:rand.uniform(1000)}",
          user_email: user_email,
          image_data: png_binary,
          input_format: "png",
          pdf_quality: Keyword.get(opts, :quality, "high"),
          strip_metadata: Keyword.get(opts, :strip_metadata, true),
          max_width: Keyword.get(opts, :max_width, 0),
          max_height: Keyword.get(opts, :max_height, 0)
        }
        |> Mcsv.V2.ImageConversionRequest.encode()

      Logger.info("Sending to User service...: #{png_size}")

      # Inject trace context into outgoing NATS message headers
      trace_headers = OtelNats.inject()
      :ok = Gnat.pub(:gnat, "user.convert.to_pdf", request, headers: trace_headers)
    end
  end
end
