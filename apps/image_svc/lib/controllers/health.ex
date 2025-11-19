defmodule HealthController do
  use ImageServiceWeb, :controller

  @moduledoc """
  Health check endpoint for load balancers and orchestration.
  """

  def check(conn, _params) do
    send_resp(conn, 200, "OK")
  end
end
