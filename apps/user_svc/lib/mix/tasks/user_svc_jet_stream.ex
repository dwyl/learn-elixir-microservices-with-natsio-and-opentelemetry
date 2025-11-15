defmodule UserSvc.JetStream do
  def setup do
    # Email stream
    # Jetstream.API.Stream.create(:gnat, %{
    #   name: "EMAIL",
    #   subjects: ["email.>"],
    #   retention: :work_queue,
    #   storage: :file,
    #   # 24 hours in nanoseconds
    #   max_age: 86_400_000_000_000,
    #   # 2 minutes deduplication
    #   duplicate_window: 120_000_000_000
    # })

    # # Image stream
    # Jetstream.API.Stream.create(:gnat, %{
    #   name: "IMAGE",
    #   subjects: ["image.>"],
    #   retention: :work_queue,
    #   storage: :file,
    #   max_age: 86_400_000_000_000
    # })
  end
end
