defmodule JetstreamSetup do
  @moduledoc """
  Centralized JetStream stream and consumer setup for all microservices.

  Each service can call this module on startup to ensure their streams exist.
  All operations are idempotent - safe to run multiple times.

  ## Example

      streams = [
        %{
          name: "EMAILS",
          subjects: ["email.>"],
          consumers: [
            %{name: "mailer", filter_subject: "email.send"},
            %{name: "confirmer", filter_subject: "email.confirm"},
            %{name: "resetter", filter_subject: "email.reset_password"}
          ]
        },
        %{
          name: "IMAGES",
          subjects: ["image.>"],
          consumers: [
            %{name: "processor", filter_subject: "image.convert"}
          ]
        }
      ]

      JetstreamSetup.setup_streams(:gnat, streams)
  """

  require Logger

  @doc """
  Sets up streams from a list of stream configurations.

  Each stream config should have:
  - `name` (required): Stream name
  - `subjects` (required): List of subject patterns
  - `consumers` (optional): List of consumer configs

  Consumer config should have:
  - `name` (required): Consumer name
  - `filter_subject` (optional): Only receive messages matching this subject
  - `ack_policy` (optional): "explicit", "all", or "none" (default: "explicit")
  - `deliver_policy` (optional): "all", "last", "new" (default: "all")
  """
  def setup_streams(connection_name \\ :gnat, streams) when is_list(streams) do
    results =
      for stream <- streams do
        with :ok <- create_stream(connection_name, stream),
             :ok <- create_consumers(connection_name, stream) do
          :ok
        else
          {:error, reason} -> {:error, {stream[:name], reason}}
        end
      end

    case Enum.filter(results, &match?({:error, _}, &1)) do
      [] -> :ok
      errors -> {:error, errors}
    end
  end

  @doc """
  Sets up JetStream from application configuration.

  Reads the stream configuration from the application environment:

      config :my_app, :jetstream_streams, [
        %{
          name: "EMAILS",
          subjects: ["email.>"],
          consumers: [
            %{name: "mailer", filter_subject: "email.send"}
          ]
        }
      ]

  Then call: `JetstreamSetup.setup_from_config(:my_app)`
  """
  def setup_from_config(app, connection_name \\ :gnat) do
    case Application.get_env(app, :jetstream_streams) do
      nil ->
        Logger.debug("[JetStream] No streams configured for #{app}")
        :ok

      streams when is_list(streams) ->
        setup_streams(connection_name, streams)

      invalid ->
        Logger.error("[JetStream] Invalid stream configuration: #{inspect(invalid)}")
        {:error, :invalid_config}
    end
  end

  @doc """
  Sets up the EMAILS stream and its consumers (legacy helper).
  """
  def setup_email_stream(connection_name \\ :gnat) do
    streams = [
      %{
        name: "EMAILS",
        subjects: ["email.>"],
        consumers: [
          %{name: "mailer", ack_policy: "explicit", deliver_policy: "all"}
        ]
      }
    ]

    setup_streams(connection_name, streams)
  end

  @doc """
  Sets up the IMAGES stream and its consumers (legacy helper).
  """
  def setup_image_stream(connection_name \\ :gnat) do
    streams = [
      %{
        name: "IMAGES",
        subjects: ["image.>"],
        consumers: []
      }
    ]

    setup_streams(connection_name, streams)
  end

  # Private helpers

  defp create_consumers(_connection_name, %{consumers: []}), do: :ok
  defp create_consumers(_connection_name, %{consumers: nil}), do: :ok

  defp create_consumers(connection_name, %{name: stream_name, consumers: consumers}) do
    results =
      for consumer <- consumers do
        create_consumer(connection_name, stream_name, consumer)
      end

    case Enum.filter(results, &match?({:error, _}, &1)) do
      [] -> :ok
      errors -> {:error, errors}
    end
  end

  defp create_stream(connection_name, %{name: name, subjects: subjects}) do
    # Use raw NATS API to avoid struct encoding issues with :domain field
    config = %{
      "name" => name,
      "subjects" => subjects
    }

    topic = "$JS.API.STREAM.CREATE.#{name}"
    message = Jason.encode!(config)

    case Gnat.request(connection_name, topic, message, receive_timeout: 5_000) do
      {:ok, %{body: body}} ->
        response = Jason.decode!(body)

        case response do
          %{"error" => error} ->
            handle_stream_error(name, error)

          %{"type" => "io.nats.jetstream.api.v1.stream_create_response"} ->
            Logger.info("[JetStream] Stream '#{name}' created successfully")
            :ok

          _ ->
            Logger.info("[JetStream] Stream '#{name}' created successfully")
            :ok
        end

      {:error, :timeout} ->
        Logger.error("[JetStream] Timeout creating stream '#{name}'")
        {:error, :timeout}

      {:error, reason} ->
        Logger.error("[JetStream] Failed to create stream '#{name}': #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp handle_stream_error(name, %{"code" => 400, "description" => "stream name already in use"}) do
    Logger.debug("[JetStream] Stream '#{name}' already exists")
    :ok
  end

  defp handle_stream_error(name, %{"err_code" => 10058}) do
    Logger.debug("[JetStream] Stream '#{name}' already exists")
    :ok
  end

  defp handle_stream_error(name, error) do
    Logger.error("[JetStream] Failed to create stream '#{name}': #{inspect(error)}")
    {:error, error}
  end

  defp create_consumer(connection_name, stream_name, consumer_config) do
    consumer_name = consumer_config[:name] || consumer_config["name"]
    ack_policy = consumer_config[:ack_policy] || consumer_config["ack_policy"] || "explicit"

    deliver_policy =
      consumer_config[:deliver_policy] || consumer_config["deliver_policy"] || "all"

    filter_subject = consumer_config[:filter_subject] || consumer_config["filter_subject"]

    # Use raw NATS API for consumer creation
    # For DURABLE endpoint: consumer name goes in BOTH the URL AND the config
    config = %{
      "durable_name" => consumer_name,
      "ack_policy" => ack_policy,
      "deliver_policy" => deliver_policy
    }

    # Add filter_subject if provided
    config =
      if filter_subject do
        Map.put(config, "filter_subject", filter_subject)
      else
        config
      end

    request_body = %{
      "stream_name" => stream_name,
      "config" => config
    }

    topic = "$JS.API.CONSUMER.DURABLE.CREATE.#{stream_name}.#{consumer_name}"
    message = Jason.encode!(request_body)

    case Gnat.request(connection_name, topic, message, receive_timeout: 5_000) do
      {:ok, %{body: body}} ->
        response = Jason.decode!(body)

        case response do
          %{"error" => error} ->
            handle_consumer_error(stream_name, consumer_name, error)

          %{"type" => "io.nats.jetstream.api.v1.consumer_create_response", "did_create" => true} ->
            Logger.info(
              "[JetStream] Consumer '#{stream_name}/#{consumer_name}' created successfully"
            )

            :ok

          %{"type" => "io.nats.jetstream.api.v1.consumer_create_response"} ->
            Logger.debug("[JetStream] Consumer '#{stream_name}/#{consumer_name}' already exists")
            :ok

          _ ->
            Logger.info("[JetStream] Consumer '#{stream_name}/#{consumer_name}' ready")

            :ok
        end

      {:error, :timeout} ->
        Logger.error("[JetStream] Timeout creating consumer '#{stream_name}/#{consumer_name}'")
        {:error, :timeout}

      {:error, reason} ->
        Logger.error(
          "[JetStream] Failed to create consumer '#{stream_name}/#{consumer_name}': #{inspect(reason)}"
        )

        {:error, reason}
    end
  end

  defp handle_consumer_error(stream_name, consumer_name, %{
         "code" => 400,
         "description" => "consumer name already in use"
       }) do
    Logger.debug("[JetStream] Consumer '#{stream_name}/#{consumer_name}' already exists")
    :ok
  end

  defp handle_consumer_error(stream_name, consumer_name, %{"err_code" => 10013}) do
    Logger.debug("[JetStream] Consumer '#{stream_name}/#{consumer_name}' already exists")
    :ok
  end

  defp handle_consumer_error(stream_name, consumer_name, error) do
    Logger.error(
      "[JetStream] Failed to create consumer '#{stream_name}/#{consumer_name}': #{inspect(error)}"
    )

    {:error, error}
  end
end
