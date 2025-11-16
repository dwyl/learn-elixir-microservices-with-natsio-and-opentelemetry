defmodule Storage do
  @moduledoc """
  Unified S3/MinIO storage client for images and PDFs.

  Provides simple store/fetch/delete operations with presigned URLs.
  Used by both user_svc and image_svc for storing original images and converted PDFs.
  """

  require Logger
  require OpenTelemetry.Tracer, as: Tracer

  @presigned_url_expiry 3600  # 1 hour

  @doc """
  Store binary data in S3/MinIO and return metadata.

  ## Parameters
    - binary: The file data to store
    - bucket: S3 bucket name
    - opts: Keyword list with optional fields:
      - key: Custom key (defaults to generated timestamp_random)
      - user_id: User identifier for logging
      - format: File extension (e.g., "png", "pdf")
      - generate_presigned_url: Whether to generate presigned URL (default: false)

  ## Returns
    {:ok, %{bucket: string, key: string, size: integer, presigned_url: string | nil}}
    {:error, reason}

  ## Examples
      iex> Storage.store(png_binary, "msvc-images", format: "png", user_id: "user123")
      {:ok, %{bucket: "msvc-images", key: "1730000000_abc123.png", size: 1024, presigned_url: nil}}

      iex> Storage.store(pdf_binary, "msvc-images", format: "pdf", generate_presigned_url: true)
      {:ok, %{bucket: "msvc-images", key: "1730000000_xyz789.pdf", size: 2048, presigned_url: "http://..."}}
  """
  def store(binary, bucket, opts \\ []) when is_binary(binary) do
    Tracer.with_span "storage.store" do
      size = byte_size(binary)
      format = Keyword.get(opts, :format, "bin")
      user_id = Keyword.get(opts, :user_id)
      key = Keyword.get(opts, :key) || generate_key(format)
      generate_url? = Keyword.get(opts, :generate_presigned_url, false)

      # Add attributes to the span
      attrs = [
        {"storage.bucket", bucket},
        {"storage.key", key},
        {"file.format", format},
        {"file.size", size}
      ]

      attrs = if user_id, do: [{"user.id", user_id} | attrs], else: attrs
      Tracer.set_attributes(attrs)

      case upload_to_s3(bucket, key, binary) do
        {:ok, _response} ->
          presigned_url = if generate_url?, do: generate_presigned_url(bucket, key), else: nil

          if presigned_url do
            Tracer.set_attribute("storage.presigned_url", presigned_url)
          end

          Tracer.add_event("storage.upload.success", [{"size", size}])
          Tracer.set_status(OpenTelemetry.status(:ok))

          {:ok, %{bucket: bucket, key: key, size: size, presigned_url: presigned_url}}

        {:error, reason} ->
          Logger.error("[Storage] Failed to upload #{key}: #{inspect(reason)}")
          Tracer.set_status(OpenTelemetry.status(:error, "Upload failed: #{inspect(reason)}"))
          Tracer.add_event("storage.upload.failed", [{"error", inspect(reason)}])
          {:error, reason}
      end
    end
  end

  @doc """
  Fetch binary data from S3/MinIO.

  ## Parameters
    - bucket: S3 bucket name
    - key: Object key

  ## Returns
    {:ok, binary}
    {:error, reason}

  ## Examples
      iex> Storage.fetch("msvc-images", "1730000000_abc123.png")
      {:ok, <<binary data>>}
  """
  def fetch(bucket, key) do
    Tracer.with_span "storage.fetch" do
      Tracer.set_attributes([
        {"storage.bucket", bucket},
        {"storage.key", key}
      ])

      case ExAws.S3.get_object(bucket, key) |> ExAws.request() do
        {:ok, %{body: body}} ->
          size = byte_size(body)
          Tracer.set_attribute("file.size", size)
          Tracer.add_event("storage.fetch.success", [{"size", size}])
          Tracer.set_status(OpenTelemetry.status(:ok))
          {:ok, body}

        {:error, reason} ->
          Logger.error("[Storage] Failed to fetch #{bucket}/#{key}: #{inspect(reason)}")
          Tracer.set_status(OpenTelemetry.status(:error, "Fetch failed: #{inspect(reason)}"))
          Tracer.add_event("storage.fetch.failed", [{"error", inspect(reason)}])
          {:error, reason}
      end
    end
  end

  @doc """
  Delete an object from S3/MinIO.

  ## Examples
      iex> Storage.delete("msvc-images", "1730000000_abc123.png")
      :ok
  """
  def delete(bucket, key) do
    Tracer.with_span "storage.delete" do
      Tracer.set_attributes([
        {"storage.bucket", bucket},
        {"storage.key", key}
      ])

      case ExAws.S3.delete_object(bucket, key) |> ExAws.request() do
        {:ok, _response} ->
          Logger.info("[Storage] Successfully deleted #{bucket}/#{key}")
          Tracer.add_event("storage.delete.success", [])
          Tracer.set_status(OpenTelemetry.status(:ok))
          :ok

        {:error, reason} ->
          Logger.error("[Storage] Failed to delete #{bucket}/#{key}: #{inspect(reason)}")
          Tracer.set_status(OpenTelemetry.status(:error, "Delete failed: #{inspect(reason)}"))
          Tracer.add_event("storage.delete.failed", [{"error", inspect(reason)}])
          {:error, reason}
      end
    end
  end

  @doc """
  List all objects in a bucket.

  ## Returns
    {:ok, [%{key: string, size: integer, last_modified: datetime}, ...]}
    {:error, reason}
  """
  def list_objects(bucket) do
    case ExAws.S3.list_objects(bucket) |> ExAws.request() do
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
  Generate a presigned GET URL for an object.

  The URL is valid for #{@presigned_url_expiry} seconds (1 hour).

  ## Examples
      iex> Storage.generate_presigned_url("msvc-images", "1730000000_abc123.png")
      "http://localhost:9000/msvc-images/1730000000_abc123.png?X-Amz-..."
  """
  def generate_presigned_url(bucket, key, expires_in \\ @presigned_url_expiry) do
    config = ExAws.Config.new(:s3)

    case ExAws.S3.presigned_url(config, :get, bucket, key, expires_in: expires_in) do
      {:ok, url} ->
        url

      {:error, reason} ->
        raise "Failed to generate presigned URL: #{inspect(reason)}"
    end
  end

  @doc """
  Generate a unique storage key with timestamp and random suffix.

  ## Examples
      iex> Storage.generate_key("png")
      "1730000000_abc123.png"
  """
  def generate_key(format \\ "bin") do
    timestamp = System.system_time(:microsecond)
    random = :crypto.strong_rand_bytes(8) |> Base.url_encode64(padding: false)
    "#{timestamp}_#{random}.#{format}"
  end

  # Private helpers

  defp upload_to_s3(bucket, key, binary) do
    # Nested span for S3 upload operation
    Tracer.with_span "storage.s3.put_object" do
      content_type = get_content_type(key)

      Tracer.set_attributes([
        {"s3.bucket", bucket},
        {"s3.key", key},
        {"content.type", content_type},
        {"content.size", byte_size(binary)}
      ])

      result =
        ExAws.S3.put_object(bucket, key, binary,
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
