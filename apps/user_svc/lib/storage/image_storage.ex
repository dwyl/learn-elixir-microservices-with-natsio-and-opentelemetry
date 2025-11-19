defmodule ImageStorage do
  @moduledoc """
  Stateless storage layer for images awaiting conversion.

  This module is a thin wrapper around the Storage module (MinIO/S3).
  It provides a simpler API for the controllers.

  ## Why Stateless?
  - Can scale horizontally across multiple nodes
  - No state to lose on restart/crash
  - MinIO is the single source of truth
  - Presigned URLs are generated on-demand (they expire anyway)
  - No memory overhead for caching
  """

  require Logger

  defp bucket do
    Application.get_env(:user_svc, :s3)
    |> Keyword.get(:image_bucket, "msvc-images")
  end

  defp expiry_bucket_retention do
    Application.get_env(:user_svc, :s3)
    |> Keyword.get(:expiry_bucket_retention, 3600)
  end

  defp access_key_id do
    Application.get_env(:user_svc, :s3)
    |> Keyword.get(:access_key_id, "minioadmin")
  end

  defp secret_access_key do
    Application.get_env(:user_svc, :s3)
    |> Keyword.get(:secret_access_key, "minioadmin")
  end

  defp object_storage_endpoint do
    Application.get_env(:user_svc, :s3)
    |> Keyword.get(:object_storage_endpoint, "http://localhost:9000")
  end

  @doc """
  Store image in MinIO.
  """
  # request.image_data, request.user_id, format
  def store(binary, job_id, user_id, user_email, mime) when is_binary(binary) do
    bucket = bucket()

    opts = [
      expiry_bucket_retention: expiry_bucket_retention(),
      object_storage_endpoint: object_storage_endpoint(),
      access_key_id: access_key_id(),
      secret_access_key: secret_access_key(),
      user_id: user_id,
      user_email: user_email
    ]

    case ReqS3Storage.store(binary, bucket, job_id, mime, opts) do
      {:ok, %{presigned_url: url, size: size, key: _key}} ->
        Logger.info(
          "[User][ImageStorage] Stored #{job_id} for user #{user_id} (#{size} bytes) at #{url}"
        )

        {:ok, {job_id, url, size}}

      {:error, {:http_error, 403}} ->
        Logger.error("[User][ImageStorage] Unauthorized to store: #{job_id}")
        OpenTelemetry.Tracer.set_status(:error, "Storage #{job_id} failed: :unauthorized")
        {:error, :unauthorized}

      {:error, reason} ->
        Logger.error("[User][ImageStorage] Failed to store: #{inspect(reason)}")
        OpenTelemetry.Tracer.set_status(:error, "Storage #{job_id} failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  # def fetch(job_id, opts) do
  #   case Storage.fetch(job_id, opts) do
  #     {:ok, binary} ->
  #       Logger.info("[User][ImageStorage] Retrieved #{job_id} (#{byte_size(binary)} bytes)")
  #       {:ok, binary}

  #     {:error, reason} ->
  #       Logger.error("[User][ImageStorage] Failed to fetch: #{inspect(reason)}")
  #       {:error, :not_found}
  #   end
  # end

  # def get_presigned_url(job_id, opts) do
  #   try do
  #     url = ReqS3Storage.generate_presigned_url(job_id, opts)
  #     Logger.debug("[User][ImageStorage] Generated presigned URL for #{job_id}")
  #     {:ok, url}
  #   rescue
  #     error ->
  #       Logger.warning("[User][ImageStorage] Failed to generate presigned URL: #{inspect(error)}")
  #       {:error, :not_found}
  #   end
  # end

  # def delete(job_id, opts) do
  #   case Storage.delete(job_id, opts) do
  #     :ok ->
  #       Logger.info("[User][ImageStorage] Deleted #{job_id}")
  #       :ok

  #     {:error, reason} ->
  #       Logger.warning("[User][ImageStorage] Failed to delete #{job_id}: #{inspect(reason)}")
  #       {:error, :not_found}
  #   end
  # end
end
