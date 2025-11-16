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
  Inject current OpenTelemetry context AND span_id into NATS-compatible headers.

  This allows the receiver to create a span link back to the original span,
  making async return paths visible in traces.

  ## Examples

      headers = OtelNats.inject_with_link()
      Gnat.pub(:gnat, "topic", message, headers: headers)
  """
  def inject_with_link do
    span_ctx = OpenTelemetry.Tracer.current_span_ctx()

    headers = :otel_propagator_text_map.inject([])
    |> Enum.map(&http_to_nats_header/1)

    # Add span_id as a custom header for linking
    if span_ctx != :undefined do
      span_id = :otel_span.span_id(span_ctx)
      trace_id = :otel_span.trace_id(span_ctx)

      headers ++ [
        {"x-span-id", span_id_to_string(span_id)},
        {"x-trace-id", trace_id_to_string(trace_id)}
      ]
    else
      headers
    end
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

  @doc """
  Extract OpenTelemetry context from NATS headers and create a span link if present.

  This creates a visual connection in trace viewers between async request/response flows.

  ## Examples

      def handle_message(%{body: body} = message) do
        headers = Map.get(message, :headers, [])
        token = OtelNats.extract_and_attach(headers)
        link = OtelNats.extract_link(headers)

        Tracer.with_span "my.span", %{links: [link]} do
          # ... process message
        end
      end
  """
  def extract_link(headers) when is_list(headers) do
    with {_, span_id_str} <- :lists.keyfind("x-span-id", 1, headers),
         {_, trace_id_str} <- :lists.keyfind("x-trace-id", 1, headers),
         {:ok, span_id} <- parse_span_id(span_id_str),
         {:ok, trace_id} <- parse_trace_id(trace_id_str) do
      # Create a span link using the OpenTelemetry API
      :opentelemetry.link(%{
        trace_id: trace_id,
        span_id: span_id,
        attributes: [],
        tracestate: []
      })
    else
      _ -> nil
    end
  end

  def extract_link(_), do: nil

  # Convert HTTP header format to NATS tuple format
  defp http_to_nats_header([key, ": ", value, "\r\n"]), do: {key, value}
  defp http_to_nats_header([key, ": ", value]), do: {key, value}
  defp http_to_nats_header({key, value}), do: {key, value}
  defp http_to_nats_header(other), do: other

  # Helper functions for span/trace ID conversion
  defp span_id_to_string(span_id) when is_integer(span_id) do
    span_id
    |> Integer.to_string(16)
    |> String.pad_leading(16, "0")
    |> String.downcase()
  end

  defp trace_id_to_string(trace_id) when is_integer(trace_id) do
    trace_id
    |> Integer.to_string(16)
    |> String.pad_leading(32, "0")
    |> String.downcase()
  end

  defp parse_span_id(span_id_str) when is_binary(span_id_str) do
    case Integer.parse(span_id_str, 16) do
      {span_id, ""} -> {:ok, span_id}
      _ -> {:error, :invalid_span_id}
    end
  end

  defp parse_trace_id(trace_id_str) when is_binary(trace_id_str) do
    case Integer.parse(trace_id_str, 16) do
      {trace_id, ""} -> {:ok, trace_id}
      _ -> {:error, :invalid_trace_id}
    end
  end
end
