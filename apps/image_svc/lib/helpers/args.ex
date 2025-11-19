defmodule Args do
  # Build args for streaming: stdin (format:-) -> stdout (pdf:-)
  def build_streaming_args(input_format, quality, threads) do
    System.put_env("MAGICK_THREAD_LIMIT", to_string(threads))

    base_args = [
      # Specify input format explicitly when reading from stdin
      # e.g., "png:-" tells ImageMagick to read PNG from stdin
      "#{input_format}:-",
      "-limit",
      "thread",
      to_string(threads)
    ]

    quality_args = quality_settings(quality)

    base_args ++ quality_args ++ ["pdf:-"]
  end

  defp quality_settings("low") do
    [
      "-quality",
      "60",
      "-density",
      "72"
    ]
  end

  defp quality_settings("medium") do
    [
      "-quality",
      "85",
      "-density",
      "100"
    ]
  end

  defp quality_settings("high") do
    [
      "-quality",
      "95",
      "-density",
      "200"
    ]
  end

  defp quality_settings("lossless") do
    [
      "-quality",
      "100",
      "-density",
      "300"
    ]
  end
end
