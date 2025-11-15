defmodule UserSvcWeb.Router do
  use UserSvcWeb, :router

  # No pipelines needed for protobuf APIs - direct routing

  # UserService.ImageLoader - Serve stored images to other services
  get("/user_svc/image_loader/v1/:job_id", ImageLoaderController, :load)

  # Health check endpoint (GET/HEAD for load balancers)
  get("/health", HealthController, :check)
  head("/health", HealthController, :check)
end
