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

  @doc """
  Store image in MinIO and return storage_id.
  """
  def store(image_binary, job_id, user_id, format \\ "png") when is_binary(image_binary) do
    case Storage.store(image_binary, job_id, user_id, format) do
      {:ok, {job_id, url, size}} ->
        Logger.info(
          "[User][ImageStorage] Stored #{job_id} for user #{user_id} (#{size} bytes) at #{url}"
        )

        {:ok, {job_id, url, size}}

      {:error, reason} ->
        Logger.error("[User][ImageStorage] Failed to store: #{inspect(reason)}")
        OpenTelemetry.Tracer.set_status(:error, "Storage #{job_id} failed: #{inspect(reason)}")
        {:error, reason}
    end
  end

  @doc """
  Retrieve an image by job_id from MinIO.

  Returns {:ok, binary} or {:error, reason}
  """
  def fetch(job_id) do
    case Storage.fetch(job_id) do
      {:ok, binary} ->
        Logger.info("[User][ImageStorage] Retrieved #{job_id} (#{byte_size(binary)} bytes)")
        {:ok, binary}

      {:error, reason} ->
        Logger.error("[User][ImageStorage] Failed to fetch: #{inspect(reason)}")
        {:error, :not_found}
    end
  end

  @doc """
  Get a presigned URL for a storage_id.

  Generates a fresh presigned URL each time (they expire after 1 hour anyway).
  """
  def get_presigned_url(job_id) do
    try do
      url = Storage.generate_presigned_url(job_id)
      Logger.debug("[User][ImageStorage] Generated presigned URL for #{job_id}")
      {:ok, url}
    rescue
      error ->
        Logger.warning("[User][ImageStorage] Failed to generate presigned URL: #{inspect(error)}")
        {:error, :not_found}
    end
  end

  @doc """
  Delete an image from MinIO storage (called after conversion is complete).
  """
  def delete(job_id) do
    case Storage.delete(job_id) do
      :ok ->
        Logger.info("[User][ImageStorage] Deleted #{job_id}")
        :ok

      {:error, reason} ->
        Logger.warning("[User][ImageStorage] Failed to delete #{job_id}: #{inspect(reason)}")
        {:error, :not_found}
    end
  end
end
