defmodule ImageSvc.ConversionOptions do
  @moduledoc """
  Builds and normalizes conversion options for ImageConverter.

  Handles defaults and normalization of protobuf request parameters.
  """

  @doc """
  Builds conversion options from protobuf request fields.

  ## Parameters
  - `input_format`: Input format string (empty string uses default "png")
  - `pdf_quality`: Quality setting (empty string uses default "high")
  - `strip_metadata`: Boolean flag for metadata stripping
  - `max_width`: Maximum width (0 means no limit)
  - `max_height`: Maximum height (0 means no limit)

  ## Returns
  Keyword list of normalized options for ImageConverter.convert/2

  ## Examples

      iex> ConversionOptions.build("", "", true, 0, 0)
      [input_format: "png", quality: "high", strip_metadata: true, max_width: nil, max_height: nil]

      iex> ConversionOptions.build("jpeg", "low", false, 800, 600)
      [input_format: "jpeg", quality: "low", strip_metadata: false, max_width: 800, max_height: 600]
  """
  def build(input_format, pdf_quality, strip_metadata, max_width, max_height) do
    [
      input_format: normalize_input_format(input_format),
      quality: normalize_quality(pdf_quality),
      strip_metadata: strip_metadata,
      max_width: normalize_dimension(max_width),
      max_height: normalize_dimension(max_height)
    ]
  end

  defp normalize_input_format(""), do: "png"

  defp normalize_input_format(format) do
    # Handle MIME types like "image/png" -> "png"
    case String.split(format, "/") do
      [_type, extension] -> String.downcase(extension)
      _ -> String.downcase(format)
    end
  end

  defp normalize_quality(""), do: "medium"
  defp normalize_quality(quality), do: quality

  defp normalize_dimension(0), do: nil
  defp normalize_dimension(dim), do: dim
end
