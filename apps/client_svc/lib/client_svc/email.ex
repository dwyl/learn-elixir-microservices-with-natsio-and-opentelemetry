defmodule Email do
  @moduledoc false

  require OpenTelemetry.Tracer, as: Tracer
  require OpenTelemetry.Span, as: Span

  @doc """
  Create a single user via NATS pub/sub.
  ## Examples

      iex> Email.create(1, :welcome)
      :ok

      iex> Email.create(2, :notification)
      :ok
  """
  @spec create(integer(), :welcome | :notification) :: :ok
  def create(i, type) do
    enum_type =
      case type do
        :welcome -> :EMAIL_TYPE_WELCOME
        :notification -> :EMAIL_TYPE_NOTIFICATION
      end

    Tracer.with_span "#{__MODULE__}.create/1" do
      Tracer.set_attribute(:type, type)

      msg =
        %Mcsv.V3.UserRequest{
          id: "#{i}",
          name: "PB User #{i}",
          email: "user#{i}@example.com",
          type: enum_type
        }
        |> Mcsv.V3.UserRequest.encode()

      # Inject trace context into outgoing NATS message headers
      trace_headers = OtelNats.inject()
      :ok = Gnat.pub(:gnat, "user.email.create", msg, headers: trace_headers)
    end
  end
end
