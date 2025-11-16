defmodule Storage do
  @moduledoc """
  S3/MinIO storage client for images and PDFs.

  Provides simple store/fetch operations with presigned URLs.
  """

  require Logger
  require OpenTelemetry.Tracer, as: Tracer

  @bucket "msvc-images"

  # 1 hour
  @presigned_url_expiry 3600

  @doc """
  Store binary data in MinIO and return a presigned GET URL.

  ## Parameters
    - binary: The file data to store
    - user_id: User identifier for logging/organization
    - format: File extension (e.g., "png", "pdf")

  ## Returns
    {:ok, %{job_id: string, presigned_url: string, size: integer}}
    {:error, reason}

  ## Examples
      iex> Storage.store(png_binary, "user123", "png")
      {:ok, %{job_id: "...", presigned_url: "http://...", size: 1024}}
  """
  def store(binary, job_id, user_id, format \\ "png") when is_binary(binary) do
    Tracer.with_span "storage.store" do
      size = byte_size(binary)

      # Add attributes (metadata) to the span
      Tracer.set_attributes([
        {"storage.id", job_id},
        {"user.id", user_id},
        {"file.format", format},
        {"file.size", size}
      ])

      name = "#{job_id}.#{format}"

      case upload_to_s3(name, binary) do
        {:ok, _response} ->
          presigned_url = generate_presigned_url(name)
          # Record success event
          Tracer.set_attribute("storage.presigned_url", presigned_url)
          Tracer.add_event("storage.upload.success", [{"size", size}])
          Tracer.set_status(OpenTelemetry.status(:ok))

          {:ok, {job_id, presigned_url, size}}

        {:error, reason} ->
          # Record error in span
          Logger.error("[User][Storage] Failed to upload #{job_id}: #{inspect(reason)}")
          Tracer.set_status(OpenTelemetry.status(:error, "Upload failed: #{inspect(reason)}"))
          Tracer.add_event("storage.upload.failed", [{"error", inspect(reason)}])
          {:error, reason}
      end
    end
  end

  @doc """
  Fetch binary data from MinIO by job_id.

  ## Parameters
    - job_id: The unique identifier returned from store/3

  ## Returns
    {:ok, binary}
    {:error, reason}

  ## Examples
      iex> Storage.fetch("1730000000_abc123.png")
      {:ok, <<binary data>>}
  """
  def fetch(job_id) do
    Tracer.with_span "storage.fetch" do
      Tracer.set_attribute("storage.id", job_id)

      case ExAws.S3.get_object(@bucket, job_id)
           |> ExAws.request() do
        {:ok, %{body: body}} ->
          size = byte_size(body)
          Tracer.set_attribute("file.size", size)
          Tracer.add_event("storage.fetch.success", [{"size", size}])
          Tracer.set_status(OpenTelemetry.status(:ok))
          {:ok, body}

        {:error, reason} ->
          Logger.error("[User][Storage] Failed to fetch #{job_id}: #{inspect(reason)}")
          Tracer.set_status(OpenTelemetry.status(:error, "Fetch failed: #{inspect(reason)}"))
          Tracer.add_event("storage.fetch.failed", [{"error", inspect(reason)}])
          {:error, reason}
      end
    end
  end

  @doc """
  Delete an object from MinIO.

  ## Examples
      iex> Storage.delete("1730000000_abc123.png")
      :ok
  """
  def delete(job_id) do
    Tracer.with_span "storage.delete" do
      Tracer.set_attribute("storage.id", job_id)

      case ExAws.S3.delete_object(@bucket, job_id)
           |> ExAws.request() do
        {:ok, _response} ->
          Logger.info("[User][Storage] Successfully delete object")
          Tracer.add_event("storage.delete.success", [])
          Tracer.set_status(OpenTelemetry.status(:ok))
          :ok

        {:error, reason} ->
          Logger.error("[User][Storage] Failed to delete #{job_id}: #{inspect(reason)}")
          Tracer.set_status(OpenTelemetry.status(:error, "Delete failed: #{inspect(reason)}"))
          Tracer.add_event("storage.delete.failed", [{"error", inspect(reason)}])
          {:error, reason}
      end
    end
  end

  @doc """
  List all objects in the bucket.

  ## Returns
    {:ok, [%{key: string, size: integer, last_modified: datetime}, ...]}
    {:error, reason}
  """
  def list_objects do
    case ExAws.S3.list_objects(@bucket) |> ExAws.request() do
      {:ok, %{body: %{contents: contents}}} ->
        objects =
          Enum.map(contents, fn obj ->
            %{
              key: obj.key,
              size: obj.size,
              last_modified: obj.last_modified
            }
          end)

        {:ok, objects}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Generate a presigned GET URL for a job_id.

  The URL is valid for #{@presigned_url_expiry} seconds (1 hour).

  ## Examples
      iex> Storage.generate_presigned_url("1730000000_abc123.png")
      "http://localhost:9000/msvc-images/1730000000_abc123.png?X-Amz-..."
  """
  def generate_presigned_url(job_id) do
    config = ExAws.Config.new(:s3)

    case ExAws.S3.presigned_url(
           config,
           :get,
           @bucket,
           job_id,
           expires_in: @presigned_url_expiry
         ) do
      {:ok, url} ->
        url

      {:error, reason} ->
        raise "Failed to generate presigned URL: #{inspect(reason)}"
    end
  end

  # Private helpers

  defp upload_to_s3(job_id, binary) do
    # Nested span for S3 upload operation
    Tracer.with_span "storage.s3.put_object" do
      content_type = get_content_type(job_id)

      Tracer.set_attributes([
        {"s3.bucket", @bucket},
        {"s3.key", job_id},
        {"content.type", content_type},
        {"content.size", byte_size(binary)}
      ])

      result =
        ExAws.S3.put_object(@bucket, job_id, binary,
          content_type: content_type,
          # Important: inline instead of attachment = view in browser
          content_disposition: "inline"
        )
        |> ExAws.request()

      case result do
        {:ok, _} -> Tracer.set_status(OpenTelemetry.status(:ok))
        {:error, err} -> Tracer.set_status(OpenTelemetry.status(:error, inspect(err)))
      end

      result
    end
  end

  defp get_content_type(filename) do
    case Path.extname(filename) do
      ".pdf" -> "application/pdf"
      ".png" -> "image/png"
      ".jpg" -> "image/jpeg"
      ".jpeg" -> "image/jpeg"
      ".gif" -> "image/gif"
      ".webp" -> "image/webp"
      _ -> "application/octet-stream"
    end
  end
end
