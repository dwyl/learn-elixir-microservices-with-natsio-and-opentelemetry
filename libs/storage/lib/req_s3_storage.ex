defmodule ReqS3Storage do
  @moduledoc """
  Modern S3/MinIO storage client using ReqS3.

  Provides a cleaner, more modern API compared to ExAws.
  Used by both user_svc and image_svc for storing original images and converted PDFs.
  """

  require Logger
  require OpenTelemetry.Tracer, as: Tracer

  @doc """
  Build S3 options from application configuration.

  Reads from the specified app's `:s3` config and returns a keyword list
  suitable for passing to other ReqS3Storage functions.

  ## Parameters
    - app_name: Application name (e.g., :user_svc, :image_svc)

  ## Returns
    Keyword list with S3 connection options

  ## Examples
      iex> ReqS3Storage.build_s3_opts(:user_svc)
      [
        object_storage_endpoint: "http://minio:9000",
        access_key_id: "minioadmin",
        secret_access_key: "minioadmin",
        region: "us-east-1",
        expiry_bucket_retention: 3600
      ]
  """
  def build_s3_opts(app_name) do
    s3_config = Application.get_env(app_name, :s3, [])

    [
      object_storage_endpoint:
        Keyword.get(s3_config, :object_storage_endpoint, "http://localhost:9000"),
      access_key_id: Keyword.get(s3_config, :access_key_id, "minioadmin"),
      secret_access_key: Keyword.get(s3_config, :secret_access_key, "minioadmin"),
      region: Keyword.get(s3_config, :region, "us-east-1"),
      expiry_bucket_retention: Keyword.get(s3_config, :expiry_bucket_retention, 3600)
    ]
  end

  @doc """
  Store binary data in S3/MinIO and return metadata.

  ## Parameters
    - binary: The file data to store
    - bucket: S3 bucket name
    - opts: Keyword list with optional fields:
      - key: Custom key (defaults to generated timestamp_random)
      - user_id: User identifier for logging
      - user_email: User email for logging
      - format: File extension (e.g., "png", "pdf")
      - generate_presigned_url: Whether to generate presigned URL (default: false)
      - expiry_bucket_retention: Presigned URL expiry in seconds (default: 3600)
      - base_url: S3 endpoint base URL (required, e.g., "http://localhost:9000")
      - access_key_id: S3 access key (required)
      - secret_access_key: S3 secret key (required)
      - region: S3 region (default: "us-east-1")

  ## Returns
    {:ok, %{bucket: string, key: string, size: integer, presigned_url: string | nil}}
    {:error, reason}

  ## Examples
      iex> ReqS3Storage.store(png_binary, "msvc-images",
      ...>   format: "png",
      ...>   user_id: "user123",
      ...>   base_url: "http://localhost:9000",
      ...>   access_key_id: "minioadmin",
      ...>   secret_access_key: "minioadmin"
      ...> )
      {:ok, %{bucket: "msvc-images", key: "1730000000_abc123.png", size: 1024, presigned_url: nil}}
  """
  def store(binary, bucket, job_id, mime, opts \\ []) when is_binary(binary) do
    Tracer.with_span "storage.store" do
      size = byte_size(binary)
      user_id = Keyword.get(opts, :user_id)
      user_email = Keyword.get(opts, :user_email)

      format = String.split(mime, "/") |> List.last() |> String.downcase()
      key = "#{job_id}.#{format}"

      # Add attributes to the span
      attrs = [
        {"storage.bucket", bucket},
        {"storage.key", key},
        {"file.format", format},
        {"file.size", size},
        {"user.email", user_email},
        {"user_id", user_id}
      ]

      Tracer.set_attributes(attrs)

      case upload_to_s3(bucket, key, binary, opts) do
        {:ok, %{status: 200}} ->
          presigned_url = generate_presigned_url(bucket, key, opts)

          Tracer.set_attribute("storage.presigned_url", presigned_url)
          Tracer.add_event("storage.upload.success", [{"size", size}])
          Tracer.set_status(OpenTelemetry.status(:ok))

          {:ok, %{bucket: bucket, key: key, size: size, presigned_url: presigned_url}}

        {:ok, %{status: status}} ->
          Logger.error("[ReqS3Storage] Failed to upload #{key}: HTTP #{status}")
          Tracer.set_status(OpenTelemetry.status(:error, "Upload failed: HTTP #{status}"))
          Tracer.add_event("storage.upload.failed", [{"http_status", status}])
          {:error, {:http_error, status}}

        {:error, reason} ->
          Logger.error("[ReqS3Storage] Failed to upload #{key}: #{inspect(reason)}")
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
    - opts: Keyword list with required fields:
      - base_url: S3 endpoint base URL
      - access_key_id: S3 access key
      - secret_access_key: S3 secret key
      - region: S3 region (default: "us-east-1")

  ## Returns
    {:ok, binary}
    {:error, reason}

  ## Examples
      iex> ReqS3Storage.fetch("msvc-images", "1730000000_abc123.png",
      ...>   base_url: "http://localhost:9000",
      ...>   access_key_id: "minioadmin",
      ...>   secret_access_key: "minioadmin"
      ...> )
      {:ok, <<binary data>>}
  """
  def fetch(bucket, key, opts \\ []) do
    Tracer.with_span "storage.fetch" do
      Tracer.set_attributes([
        {"storage.bucket", bucket},
        {"storage.key", key}
      ])

      req = build_req(opts)

      case Req.get(req, url: "s3://#{bucket}/#{key}") do
        {:ok, %{status: 200, body: body}} ->
          size = byte_size(body)
          Tracer.set_attribute("file.size", size)
          Tracer.add_event("storage.fetch.success", [{"size", size}])
          Tracer.set_status(OpenTelemetry.status(:ok))
          {:ok, body}

        {:ok, %{status: status}} ->
          Logger.error("[ReqS3Storage] Failed to fetch #{bucket}/#{key}: HTTP #{status}")
          Tracer.set_status(OpenTelemetry.status(:error, "Fetch failed: HTTP #{status}"))
          Tracer.add_event("storage.fetch.failed", [{"http_status", status}])
          {:error, {:http_error, status}}

        {:error, reason} ->
          Logger.error("[ReqS3Storage] Failed to fetch #{bucket}/#{key}: #{inspect(reason)}")
          Tracer.set_status(OpenTelemetry.status(:error, "Fetch failed: #{inspect(reason)}"))
          Tracer.add_event("storage.fetch.failed", [{"error", inspect(reason)}])
          {:error, reason}
      end
    end
  end

  @doc """
  Check if an object exists in S3/MinIO by performing a HEAD request.

  ## Parameters
    - bucket: S3 bucket name
    - key: Object key
    - opts: Keyword list with required fields (same as other functions)

  ## Returns
    {:ok, %{content_length: integer, last_modified: string, ...}}
    {:error, %{status: 404}} if not found
    {:error, reason}

  ## Examples
      iex> ReqS3Storage.head_object("msvc-images", "test.png",
      ...>   base_url: "http://localhost:9000",
      ...>   access_key_id: "minioadmin",
      ...>   secret_access_key: "minioadmin"
      ...> )
      {:ok, %{content_length: 1024, last_modified: "2024-01-01T00:00:00Z"}}
  """
  def head_object(bucket, key, opts \\ []) do
    Tracer.with_span "storage.head_object" do
      Tracer.set_attributes([
        {"storage.bucket", bucket},
        {"storage.key", key}
      ])

      req = build_req(opts)

      case Req.head(req, url: "s3://#{bucket}/#{key}") do
        {:ok, %Req.Response{status: 200, headers: headers} = _response} ->
          # Extract content-length, handling both list and string formats
          content_length =
            case headers["content-length"] || headers[:content_length] do
              [length_str] when is_binary(length_str) -> String.to_integer(length_str)
              length_str when is_binary(length_str) -> String.to_integer(length_str)
              length_int when is_integer(length_int) -> length_int
              _ -> 0
            end

          # Extract last-modified
          last_modified =
            case headers["last-modified"] || headers[:last_modified] do
              [date_str] -> date_str
              date_str when is_binary(date_str) -> date_str
              _ -> nil
            end

          metadata = %{
            content_length: content_length,
            last_modified: last_modified
          }

          Logger.debug(
            "[ReqS3Storage] HEAD #{bucket}/#{key}: exists (#{metadata.content_length} bytes)"
          )

          Tracer.set_status(OpenTelemetry.status(:ok))
          {:ok, metadata}

        {:ok, %{status: 404} = response} ->
          Logger.debug("[ReqS3Storage] HEAD #{bucket}/#{key}: not found (404)")
          Tracer.set_status(OpenTelemetry.status(:error, "Object not found"))
          {:error, response}

        {:ok, %{status: status} = response} ->
          Logger.error("[ReqS3Storage] HEAD #{bucket}/#{key}: HTTP #{status}")
          Tracer.set_status(OpenTelemetry.status(:error, "HEAD failed: HTTP #{status}"))
          {:error, response}

        {:error, reason} ->
          Logger.error("[ReqS3Storage] HEAD #{bucket}/#{key}: #{inspect(reason)}")
          Tracer.set_status(OpenTelemetry.status(:error, "HEAD failed: #{inspect(reason)}"))
          {:error, reason}
      end
    end
  end

  @doc """
  Delete an object from S3/MinIO.

  ## Examples
      iex> ReqS3Storage.delete("msvc-images", "1730000000_abc123.png",
      ...>   base_url: "http://localhost:9000",
      ...>   access_key_id: "minioadmin",
      ...>   secret_access_key: "minioadmin"
      ...> )
      :ok
  """
  def delete(bucket, key, opts \\ []) do
    Tracer.with_span "storage.delete" do
      Tracer.set_attributes([
        {"storage.bucket", bucket},
        {"storage.key", key}
      ])

      req = build_req(opts)

      case Req.delete(req, url: "s3://#{bucket}/#{key}") do
        {:ok, %{status: status}} when status in 200..299 ->
          Logger.info("[ReqS3Storage] Successfully deleted #{bucket}/#{key}")
          Tracer.add_event("storage.delete.success", [])
          Tracer.set_status(OpenTelemetry.status(:ok))
          :ok

        {:ok, %{status: status}} ->
          Logger.error("[ReqS3Storage] Failed to delete #{bucket}/#{key}: HTTP #{status}")
          Tracer.set_status(OpenTelemetry.status(:error, "Delete failed: HTTP #{status}"))
          Tracer.add_event("storage.delete.failed", [{"http_status", status}])
          {:error, {:http_error, status}}

        {:error, reason} ->
          Logger.error("[ReqS3Storage] Failed to delete #{bucket}/#{key}: #{inspect(reason)}")
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
  def list_objects(bucket, opts \\ []) do
    req = build_req(opts)

    case Req.get(req, url: "s3://#{bucket}") do
      {:ok, %{status: 200, body: body}} ->
        # S3 XML response structure: %{"ListBucketResult" => %{"Contents" => [...]}}
        # Try different possible nested structures
        contents_raw =
          get_in(body, ["ListBucketResult", "Contents"]) ||
            get_in(body, [:list_bucket_result, :contents]) ||
            body["Contents"] ||
            body[:contents] ||
            []

        # S3 XML response can have different structures:
        # - Empty bucket: no contents key
        # - Single object: contents is a map (not a list)
        # - Multiple objects: contents is a list of maps
        contents =
          case contents_raw do
            nil -> []
            [] -> []
            items when is_list(items) -> items
            single_item when is_map(single_item) -> [single_item]
          end

        objects =
          Enum.map(contents, fn obj ->
            # S3 uses capitalized string keys: "Key", "Size", "LastModified"
            key = obj["Key"] || obj[:key] || obj[:Key] || ""

            # Size comes as a string, need to parse it
            size =
              case obj["Size"] || obj[:size] || obj[:Size] do
                size_str when is_binary(size_str) -> String.to_integer(size_str)
                size_int when is_integer(size_int) -> size_int
                _ -> 0
              end

            # LastModified is an ISO8601 string, parse to DateTime
            last_modified =
              case obj["LastModified"] || obj[:last_modified] || obj[:LastModified] do
                date_str when is_binary(date_str) ->
                  case DateTime.from_iso8601(date_str) do
                    {:ok, dt, _} -> dt
                    {:error, _} -> nil
                  end

                dt ->
                  dt
              end

            %{
              key: key,
              size: size,
              last_modified: last_modified
            }
          end)

        Logger.debug("[ReqS3Storage] Listed #{length(objects)} objects from bucket #{bucket}")
        {:ok, objects}

      {:ok, %{status: status}} ->
        Logger.error("[ReqS3Storage] Failed to list objects: HTTP #{status}")
        {:error, {:http_error, status}}

      {:error, reason} ->
        Logger.error("[ReqS3Storage] Failed to list objects: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Generate a presigned GET URL for an object.

  The URL is valid for `expires_in` seconds.
  Pass `expires_in` or `expiry_bucket_retention` in opts to override the default (3600 = 1 hour).

  ## Examples
      iex> ReqS3Storage.generate_presigned_url("msvc-images", "1730000000_abc123.png",
      ...>   base_url: "http://localhost:9000",
      ...>   access_key_id: "minioadmin",
      ...>   secret_access_key: "minioadmin",
      ...>   expiry_bucket_retention: 7200
      ...> )
      "http://localhost:9000/msvc-images/1730000000_abc123.png?X-Amz-Algorithm=..."
  """
  def generate_presigned_url(bucket, key, opts \\ []) do
    # Build options for ReqS3.presign_url
    presign_opts = [
      bucket: bucket,
      key: key,
      access_key_id: Keyword.fetch!(opts, :access_key_id),
      secret_access_key: Keyword.fetch!(opts, :secret_access_key),
      region: Keyword.get(opts, :region, "us-east-1"),
      endpoint_url: Keyword.fetch!(opts, :object_storage_endpoint)
    ]

    ReqS3.presign_url(presign_opts)
  end

  @doc """
  Stream data directly to S3/MinIO using ExAws multipart upload.

  This allows uploading large files without loading them into memory.
  ExAws.S3.upload automatically handles multipart chunking at 5MB boundaries
  (S3 minimum part size).

  **Important**: The input stream does not need to emit chunks of exactly 5MB.
  ExAws.S3.upload will buffer and rechunk as needed. Your stream can emit any
  chunk size (e.g., 64KB from ExCmd), and ExAws will handle the rest.

  ## Parameters
    - stream: Enumerable stream of binary chunks (any chunk size accepted)
    - bucket: S3 bucket name
    - job_id: Job identifier (will be used to generate key with format)
    - mime: MIME type (e.g., "application/pdf")
    - opts: Keyword list with required fields:
      - object_storage_endpoint: S3 endpoint URL
      - access_key_id: S3 access key
      - secret_access_key: S3 secret key
      - region: S3 region (default: "us-east-1")

  ## Returns
    {:ok, %{bucket: string, key: string, size: integer, presigned_url: string}}
    {:error, reason}

  ## Examples
      iex> stream = File.stream!("large_file.pdf", [], 65_536)
      iex> ReqS3Storage.store_stream(stream, "msvc-images", "job_123", "application/pdf",
      ...>   object_storage_endpoint: "http://localhost:9000",
      ...>   access_key_id: "minioadmin",
      ...>   secret_access_key: "minioadmin"
      ...> )
      {:ok, %{bucket: "msvc-images", key: "job_123.pdf", size: 1048576, presigned_url: "..."}}
  """
  def store_stream(stream, bucket, job_id, mime, opts \\ []) do
    Tracer.with_span "storage.store_stream" do
      format = String.split(mime, "/") |> List.last() |> String.downcase()
      key = "#{job_id}.#{format}"

      Tracer.set_attributes([
        {"storage.bucket", bucket},
        {"storage.key", key},
        {"file.format", format},
        {"upload.method", "multipart_stream"}
      ])

      Logger.info("[ReqS3Storage] Starting streaming upload: #{bucket}/#{key}")

      # Configure ExAws with endpoint and credentials
      ex_aws_config = [
        scheme: get_scheme(opts),
        host: get_host(opts),
        port: get_port(opts),
        region: Keyword.get(opts, :region, "us-east-1"),
        access_key_id: Keyword.fetch!(opts, :access_key_id),
        secret_access_key: Keyword.fetch!(opts, :secret_access_key)
      ]

      # Stream upload with automatic multipart handling
      # ExAws.S3.upload/4 creates an upload operation with the stream as source
      # The stream is automatically chunked at 5MB (S3 minimum part size) during upload
      upload_opts = [
        content_type: get_content_type(key),
        content_disposition: "inline"
      ]

      result =
        stream
        |> ExAws.S3.upload(bucket, key, upload_opts)
        |> ExAws.request(ex_aws_config)

      case result do
        {:ok, %{status_code: 200}} ->
          # Generate presigned URL
          presigned_url = generate_presigned_url(bucket, key, opts)

          # Size is unknown for streams - could track with reduce if needed
          size = 0

          Logger.info("[ReqS3Storage] Streaming upload complete: #{bucket}/#{key}")

          Tracer.set_attribute("storage.presigned_url", presigned_url)
          Tracer.add_event("storage.upload.success", [{"method", "stream"}])
          Tracer.set_status(OpenTelemetry.status(:ok))

          {:ok, %{bucket: bucket, key: key, size: size, presigned_url: presigned_url}}

        {:ok, response} ->
          Logger.error("[ReqS3Storage] Streaming upload failed: #{inspect(response)}")
          Tracer.set_status(OpenTelemetry.status(:error, "Upload failed"))
          Tracer.add_event("storage.upload.failed", [{"response", inspect(response)}])
          {:error, {:upload_failed, response}}

        {:error, reason} ->
          Logger.error("[ReqS3Storage] Streaming upload failed: #{inspect(reason)}")
          Tracer.set_status(OpenTelemetry.status(:error, inspect(reason)))
          Tracer.add_event("storage.upload.failed", [{"error", inspect(reason)}])
          {:error, reason}
      end
    end
  end

  @doc """
  Generate a unique storage key with timestamp and random suffix.

  ## Examples
      iex> ReqS3Storage.generate_key("png")
      "1730000000_abc123.png"
  """
  def generate_key(format) do
    timestamp = System.system_time(:microsecond)
    random = :crypto.strong_rand_bytes(8) |> Base.url_encode64(padding: false)
    "#{timestamp}_#{random}.#{format}"
  end

  def build_req(opts) do
    access_key_id = Keyword.fetch!(opts, :access_key_id)
    secret_access_key = Keyword.fetch!(opts, :secret_access_key)
    object_storage_endpoint = Keyword.fetch!(opts, :object_storage_endpoint)
    region = Keyword.get(opts, :region, "us-east-1")

    Req.new()
    |> ReqS3.attach(
      aws_endpoint_url_s3: object_storage_endpoint,
      aws_sigv4: [
        access_key_id: access_key_id,
        secret_access_key: secret_access_key,
        region: region
      ]
    )
  end

  defp upload_to_s3(bucket, key, binary, opts) do
    # Nested span for S3 upload operation
    Tracer.with_span "storage.s3.put_object" do
      content_type = get_content_type(key)

      Tracer.set_attributes([
        {"s3.bucket", bucket},
        {"s3.key", key},
        {"content.type", content_type},
        {"content.size", byte_size(binary)}
      ])

      req = build_req(opts)

      result =
        Req.put(req,
          url: "s3://#{bucket}/#{key}",
          body: binary,
          headers: [
            {"content-type", content_type},
            # Important: inline instead of attachment = view in browser
            {"content-disposition", "inline"}
          ]
        )

      case result do
        {:ok, %{status: status}} when status in 200..299 ->
          Tracer.set_status(OpenTelemetry.status(:ok))
          result

        {:ok, %{status: status}} ->
          Tracer.set_status(OpenTelemetry.status(:error, "HTTP #{status}"))
          {:error, {:http_error, status}}

        {:error, err} ->
          Tracer.set_status(OpenTelemetry.status(:error, inspect(err)))
          {:error, err}
      end
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

  # Parse endpoint URL into components for ExAws
  defp get_scheme(opts) do
    endpoint = Keyword.fetch!(opts, :object_storage_endpoint)
    uri = URI.parse(endpoint)
    uri.scheme
  end

  defp get_host(opts) do
    endpoint = Keyword.fetch!(opts, :object_storage_endpoint)
    uri = URI.parse(endpoint)
    uri.host
  end

  defp get_port(opts) do
    endpoint = Keyword.fetch!(opts, :object_storage_endpoint)
    uri = URI.parse(endpoint)
    uri.port
  end
end
