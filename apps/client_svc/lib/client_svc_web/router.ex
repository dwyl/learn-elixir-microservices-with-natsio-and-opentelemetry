defmodule ClientServiceWeb.Router do
  use ClientServiceWeb, :router

  @moduledoc false

  get("/health", HealthController, :check)
  head("/health", HealthController, :check)
end
