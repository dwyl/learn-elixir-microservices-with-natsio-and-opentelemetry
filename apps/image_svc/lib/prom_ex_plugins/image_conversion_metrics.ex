defmodule PromExPlugin.ImageConversionMetrics do
  @moduledoc """
  Custom PromEx plugin for image conversion metrics.

  Exposes Prometheus metrics for:
  - ImageMagick conversion duration
  - Image sizes (input/output)
  - Conversion quality settings
  - Success/failure rates
  """
  use PromEx.Plugin

  @impl true
  def event_metrics(_opts) do
    [
      # Image conversion metrics
      conversion_metrics()
    ]
  end

  defp conversion_metrics do
    Event.build(
      :image_svc_conversion_metrics,
      [
        # Histogram of conversion duration
        distribution(
          "image_conversion.duration.milliseconds",
          event_name: [:image_svc, :conversion, :complete],
          measurement: :duration,
          description: "Time taken to convert image to PDF",
          reporter_options: [
            buckets: [10, 25, 50, 100, 250, 500, 1000, 2500, 5000, 10_000, 20_000, 40_000, 60_000]
          ],
          tag_values: fn metadata ->
            %{
              quality: metadata.quality,
              method: metadata.method
            }
          end,
          tags: [:quality, :method],
          unit: :millisecond
        ),

        # Distribution of output file sizes
        distribution(
          "image_conversion.output_size.bytes",
          event_name: [:image_svc, :conversion, :complete],
          measurement: :size_bytes,
          description: "Size of converted PDF in bytes",
          reporter_options: [
            buckets: [1_000, 10_000, 50_000, 100_000, 500_000, 1_000_000, 5_000_000]
          ],
          tag_values: fn metadata ->
            %{
              quality: metadata.quality
            }
          end,
          tags: [:quality],
          unit: :byte
        ),

        # Counter of total conversions
        counter(
          "image_conversion.total",
          event_name: [:image_svc, :conversion, :complete],
          description: "Total number of image conversions",
          tag_values: fn metadata ->
            %{
              quality: metadata.quality,
              method: metadata.method
            }
          end,
          tags: [:quality, :method]
        )
      ]
    )
  end
end
