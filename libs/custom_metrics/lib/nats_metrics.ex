defmodule PromExPlugin.NatsMetrics do
  @moduledoc """
  PromEx plugin for NATS (Gnat) telemetry metrics.

  Tracks messaging layer performance:
  - Publish latency (how long does Gnat.pub take?)
  - Message received counts (throughput per topic)
  - Request/reply latency (for request/response patterns)
  - Subscription events (sub/unsub)

  ## Usage

  Add to your PromEx module:

      def plugins do
        [
          PromExPlugin.NatsMetrics
        ]
      end

  ## Metrics Exposed

  - `gnat_pub_duration_microseconds` - Histogram of publish latency
  - `gnat_message_received_total` - Counter of messages received per topic
  - `gnat_request_duration_microseconds` - Histogram of request/reply latency
  - `gnat_subscription_total` - Counter of subscriptions created
  - `gnat_unsubscription_total` - Counter of unsubscriptions

  ## Grafana Queries

  Average publish latency per topic:
  ```promql
  rate(gnat_pub_duration_microseconds_sum[1m]) /
  rate(gnat_pub_duration_microseconds_count[1m])
  ```

  Message throughput per topic:
  ```promql
  rate(gnat_message_received_total[1m])
  ```

  P95 request latency:
  ```promql
  histogram_quantile(0.95,
    rate(gnat_request_duration_microseconds_bucket[1m])
  )
  ```
  """
  use PromEx.Plugin

  @impl true
  def event_metrics(_opts) do
    [
      nats_metrics()
    ]
  end

  defp nats_metrics do
    Event.build(
      :nats_gnat_metrics,
      [
        # Publish latency histogram
        distribution(
          "gnat.pub.duration.microseconds",
          event_name: [:gnat, :pub],
          measurement: :latency,
          description: "NATS publish latency (time to send message to NATS server)",
          reporter_options: [
            buckets: [10, 50, 100, 250, 500, 1_000, 2_500, 5_000, 10_000]
          ],
          tag_values: &extract_topic/1,
          tags: [:topic],
          unit: {:native, :microsecond}
        ),

        # Messages received counter
        counter(
          "gnat.message_received.total",
          event_name: [:gnat, :message_received],
          description: "Total NATS messages received by topic",
          tag_values: &extract_topic/1,
          tags: [:topic]
        ),

        # Request/reply latency histogram
        distribution(
          "gnat.request.duration.microseconds",
          event_name: [:gnat, :request],
          measurement: :latency,
          description: "NATS request/reply latency (time from request to response)",
          reporter_options: [
            buckets: [100, 500, 1_000, 2_500, 5_000, 10_000, 25_000, 50_000]
          ],
          tag_values: &extract_topic/1,
          tags: [:topic],
          unit: {:native, :microsecond}
        ),

        # Subscription counter
        counter(
          "gnat.subscription.total",
          event_name: [:gnat, :sub],
          description: "Total NATS subscriptions created",
          tag_values: &extract_topic/1,
          tags: [:topic]
        ),

        # Unsubscription counter
        counter(
          "gnat.unsubscription.total",
          event_name: [:gnat, :unsub],
          description: "Total NATS unsubscriptions",
          tag_values: &extract_topic/1,
          tags: [:topic]
        )
      ]
    )
  end

  # Extract topic from telemetry metadata
  defp extract_topic(%{topic: topic}) when is_binary(topic), do: %{topic: topic}
  defp extract_topic(_), do: %{topic: "unknown"}
end
