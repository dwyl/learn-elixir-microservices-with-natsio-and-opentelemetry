defmodule ImageServiceWeb.Endpoint do
  @moduledoc """
  The Promex.Plug is added before Plug.Telemetry to avoid self-instrumentation.

  The Plug.Parsers is configured to accept protobuf and plain text formats besides Json.

  The Phoenix telemetry emits events for OTEL.
  """

  use Phoenix.Endpoint, otp_app: :image_svc

  plug(PromEx.Plug, prom_ex_module: ImageService.PromEx)

  # Request ID for distributed tracing correlation
  plug(Plug.RequestId)

  plug(Plug.Telemetry, event_prefix: [:phoenix, :endpoint])

  plug(Plug.Parsers,
    parsers: [:json],
    pass: ["application/protobuf", "application/x-protobuf"],
    json_decoder: Jason
  )

  # HEAD request support (OPTIONS/HEAD for health checks)
  plug(Plug.Head)

  plug(ImageServiceWeb.Router)
end
