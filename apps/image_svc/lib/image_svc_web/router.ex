defmodule ImageServiceWeb.Router do
  use ImageServiceWeb, :router
  @moduledoc false

  # Health check endpoint (GET/HEAD for load balancers)
  get("/health", HealthController, :check)
  head("/health", HealthController, :check)
end
