defmodule UserServiceWeb do
  @moduledoc """
  The entrypoint for defining your web interface (controllers, routers).

  This can be used in your application as:

      use UserSvcWeb, :controller
      use UserSvcWeb, :router

  The definitions below will be executed for every controller,
  so keep them short and clean.
  """

  # def static_paths, do: []  # No static assets

  def router do
    quote do
      use Phoenix.Router, helpers: false

      import Plug.Conn
      import Phoenix.Controller
    end
  end

  def controller do
    quote do
      use Phoenix.Controller, formats: [:json]

      import Plug.Conn

      # OpenTelemetry helpers (for manual spans if needed)
      require OpenTelemetry.Tracer, as: Tracer
    end
  end

  @doc """
  When used, dispatch to the appropriate controller/router/etc.
  """
  defmacro __using__(which) when is_atom(which) do
    apply(__MODULE__, which, [])
  end
end
