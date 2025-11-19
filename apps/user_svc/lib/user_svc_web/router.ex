defmodule UserServiceWeb.Router do
  use UserServiceWeb, :router

  # No pipelines needed for protobuf APIs - direct routing

  # Health check endpoint (GET/HEAD for load balancers)
  get("/health", HealthController, :check)
  head("/health", HealthController, :check)
end
