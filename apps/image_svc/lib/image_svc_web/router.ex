defmodule ImageSvcWeb.Router do
  use ImageSvcWeb, :router
  @moduledoc false

  # Health check endpoint (GET/HEAD for load balancers)
  get("/health", HealthController, :check)
  head("/health", HealthController, :check)
end
