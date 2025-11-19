defmodule ImageMagick do
  @moduledoc """
  ImageMagick utilities for image identification and format detection.

  Note: ImageMagick uses Ghostscript internally for PDF rendering.
  Both tools must be installed for image-to-PDF conversion to work.
  """

  require Logger
  require OpenTelemetry.Tracer

  @doc """
  Check if required image processing tools are installed.

  We need both:
  - ImageMagick (`magick`) for image format detection and conversion
  - Ghostscript (`gs`) for PDF rendering (used internally by ImageMagick)

  ## Examples

      iex> ImageMagick.check()
      :ok
  """
  def check do
    with {:ok, magick_version} <- check_imagemagick(),
         {:ok, gs_version} <- check_ghostscript() do
      Logger.info("[ImageMagick] ImageMagick: #{magick_version}")
      Logger.info("[ImageMagick] Ghostscript: #{gs_version}")
      :ok
    else
      {:error, reason} ->
        Logger.error("[ImageMagick] Startup check failed: #{reason}")
        raise reason
    end
  end

  defp check_imagemagick do
    case System.cmd("magick", ["-version"]) do
      {output, 0} ->
        version =
          output
          |> String.split("\n")
          |> List.first()
          |> String.trim()

        {:ok, version}

      {_error, _} ->
        {:error, "ImageMagick not found - required for image format detection"}
    end
  end

  defp check_ghostscript do
    case System.cmd("gs", ["--version"]) do
      {output, 0} ->
        version = String.trim(output)
        {:ok, "Ghostscript #{version}"}

      {_error, _} ->
        {:error, "Ghostscript not found - required for PDF conversion"}
    end
  end
end
