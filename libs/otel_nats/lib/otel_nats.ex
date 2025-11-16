defmodule OtelNats do
  @moduledoc """
  Helper functions for OpenTelemetry context propagation through NATS.

  The `:otel_propagator_text_map` module works with HTTP headers in the format
  `["key", ": ", "value", "\\r\\n"]`, but NATS uses simple tuples `{key, value}`.
  This module converts between the two formats.
  """

  @doc """
  Inject current OpenTelemetry context into NATS-compatible headers.

  ## Examples

      headers = OtelNats.inject()
      Gnat.pub(:gnat, "topic", message, headers: headers)
  """
  def inject do
    :otel_propagator_text_map.inject([])
    |> Enum.map(&http_to_nats_header/1)
  end

  @doc """
  Extract OpenTelemetry context from NATS headers and attach it.

  ## Examples

      def handle_message(%{body: body} = message) do
        headers = Map.get(message, :headers, [])
        OtelNats.extract_and_attach(headers)
        # ... process message
      end
  """
  def extract_and_attach(headers) when is_list(headers) do
    # Keep headers as a list of tuples (carrier)
    carrier = headers

    # Get the configured text map propagator
    propagator = :opentelemetry.get_text_map_extractor()

    # Custom getter function that handles NATS tuple format
    # Signature: get_header(Key, Carrier) -> Value | :undefined
    # The propagator calls it as: CarrierGet(Key, Carrier)
    getter_fun = fn key, carr ->
      case :lists.keyfind(key, 1, carr) do
        {^key, value} -> value
        false -> :undefined
      end
    end

    # Custom keys function - returns all header keys
    # Signature: keys_fun(Carrier) -> [Keys]
    keys_fun = fn carr ->
      for {key, _value} <- carr, do: key
    end

    # Extract with custom getter/keys functions
    # Signature: extract(Propagator, Carrier, CarrierKeysFun, CarrierGetFun) -> Token
    # Note: extract() internally calls attach() and returns the token
    :otel_propagator_text_map.extract(propagator, carrier, keys_fun, getter_fun)
  end

  def extract_and_attach(_) do
    # Empty carrier when no headers provided - extract() will create a new trace
    empty_carrier = []
    propagator = :opentelemetry.get_text_map_extractor()
    getter_fun = fn _key, _carr -> :undefined end
    keys_fun = fn _carr -> [] end
    :otel_propagator_text_map.extract(propagator, empty_carrier, keys_fun, getter_fun)
  end

  # Convert HTTP header format to NATS tuple format
  defp http_to_nats_header([key, ": ", value, "\r\n"]), do: {key, value}
  defp http_to_nats_header([key, ": ", value]), do: {key, value}
  defp http_to_nats_header({key, value}), do: {key, value}
  defp http_to_nats_header(other), do: other

  # Convert NATS tuple format to HTTP header format
  # defp nats_to_http_header({key, value}), do: [key, ": ", value, "\r\n"]
  # defp nats_to_http_header(other), do: other
end
