defmodule HealthController do
  @moduledoc """
  Health check controller for user_svc.
  """

  use UserServiceWeb, :controller

  @doc """
  Health check
  """
  def check(conn, _) do
    send_resp(conn, 200, "OK")
  end
end
