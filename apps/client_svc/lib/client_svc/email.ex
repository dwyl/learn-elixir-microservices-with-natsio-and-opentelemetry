defmodule Email do
  @moduledoc false

  require OpenTelemetry.Tracer, as: Tracer
  require OpenTelemetry.Span, as: Span

  @doc """
  Create a single user via NATS pub/sub.
  """
  def create(i) do
    Tracer.with_span "#{__MODULE__}.create/1" do
      Tracer.set_attribute(:value, i)

      msg =
        %Mcsv.V2.UserRequest{
          id: "#{i}",
          name: "PB User #{i}",
          email: "user#{i}@example.com",
          type: :EMAIL_TYPE_NOTIFICATION
        }
        |> Mcsv.V2.UserRequest.encode()

      # Inject trace context into outgoing NATS message headers
      trace_headers = OtelNats.inject()
      :ok = Gnat.pub(:gnat, "user.email.create", msg, headers: trace_headers)
    end
  end
end
