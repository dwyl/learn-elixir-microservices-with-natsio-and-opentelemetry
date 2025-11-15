defmodule UserSvc.MinIOCleaner do
  use GenServer
  require Logger

  # Run daily
  @cleanup_interval :timer.hours(24)
  # Delete files older than 7 days
  @max_age_days 7

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
    bucket = Application.get_env(:user_svc, :image_bucket)
    cutoff_date = DateTime.utc_now() |> DateTime.add(-@max_age_days, :day)

    case ExAws.S3.list_objects(bucket) |> ExAws.request() do
      {:ok, %{body: %{contents: objects}}} ->
        objects
        |> Enum.filter(fn obj ->
          DateTime.compare(obj.last_modified, cutoff_date) == :lt
        end)
        |> Enum.each(fn obj ->
          Logger.info("[MinIOCleaner] Deleting old file: #{obj.key}")
          ExAws.S3.delete_object(bucket, obj.key) |> ExAws.request()
        end)

      {:error, reason} ->
        Logger.error("[MinIOCleaner] Failed to list objects: #{inspect(reason)}")
    end
  end
end
