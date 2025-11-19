defmodule UserService.MinIOCleaner do
  use GenServer
  require Logger

  @moduledoc """
  A GenServer that periodically cleans up old images from MinIO.
  It deletes images older than a specified age from the configured image bucket.
  """

  # Run every 15 minutes
  @cleanup_interval :timer.minutes(15)
  # Delete files older than 1 hour
  @max_age_seconds 3600

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @impl true
  def init(state) do
    # Schedule first cleanup
    schedule_cleanup()
    {:ok, state}
  end

  @impl true
  def handle_info(:cleanup, state) do
    Logger.info("[MinIOCleaner] Starting cleanup...")

    cleanup_old_images()

    # Schedule next cleanup
    schedule_cleanup()
    {:noreply, state}
  end

  defp schedule_cleanup do
    Process.send_after(self(), :cleanup, @cleanup_interval)
  end

  defp cleanup_old_images do
    s3_config = Application.get_env(:user_svc, :s3)
    bucket = Keyword.get(s3_config, :image_bucket, "msvc-images")
    cutoff_date = DateTime.utc_now() |> DateTime.add(-@max_age_seconds, :second)

    opts = [
      object_storage_endpoint:
        Keyword.get(s3_config, :object_storage_endpoint, "http://localhost:9000"),
      access_key_id: Keyword.get(s3_config, :access_key_id, "minioadmin"),
      secret_access_key: Keyword.get(s3_config, :secret_access_key, "minioadmin"),
      region: Keyword.get(s3_config, :region, "us-east-1")
    ]

    case ReqS3Storage.list_objects(bucket, opts) do
      {:ok, objects} ->
        Logger.info("[MinIOCleaner] Found #{length(objects)} total objects in bucket #{bucket}")
        Logger.debug("[MinIOCleaner] Objects: #{inspect(objects)}")
        Logger.info("[MinIOCleaner] Cutoff date: #{cutoff_date}")

        deleted_count =
          objects
          |> Enum.filter(fn obj ->
            DateTime.compare(obj.last_modified, cutoff_date) == :lt
          end)
          |> Enum.reduce(0, fn obj, count ->
            Logger.info(
              "[MinIOCleaner] Deleting old file: #{obj.key} (last modified: #{obj.last_modified})"
            )

            case ReqS3Storage.delete(bucket, obj.key, opts) do
              :ok ->
                count + 1

              {:error, reason} ->
                Logger.error("[MinIOCleaner] Failed to delete #{obj.key}: #{inspect(reason)}")
                count
            end
          end)

        Logger.info("[MinIOCleaner] Cleanup complete. Deleted #{deleted_count} old files.")

      {:error, reason} ->
        Logger.error("[MinIOCleaner] Failed to list objects: #{inspect(reason)}")
    end
  end
end
