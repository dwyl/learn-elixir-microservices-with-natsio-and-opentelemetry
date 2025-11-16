defmodule ImageSvc.MixProject do
  use Mix.Project

  def project do
    [
      app: :image_svc,
      version: "0.1.0",
      config_path: "config/config.exs",
      deps_path: "deps",
      lockfile: "mix.lock",
      elixir: "~> 1.19",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      releases: releases(),
      aliases: aliases()
    ]
  end

  defp aliases do
    [
      "protos.refresh": [
        "deps.clean protos --build",
        "deps.get",
        "compile --force"
      ],
      refresh: ["format", "protos.refresh", "dialyzer", "credo"]
    ]
  end

  defp releases do
    [
      image_svc: [
        applications: [
          opentelemetry_exporter: :permanent,
          opentelemetry: :temporary
        ],
        # include_erts: true,
        include_executables_for: [:unix]
        # steps: [:assemble, &Bakeware.assemble/1],
        # compiler_options: [
        # Remove debug info
        # debug_info: false,
        # Inline list functions
        # inline_list_funs: true,
        # Inline functions up to 100 ops
        # inline_size: 100
        # ]
      ]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [
        :logger,
        :os_mon,
        # :inets,
        :tls_certificate_check
      ],
      mod: {ImageService.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:libcluster, "~> 3.5"},
      {:bandit, "~> 1.8"},
      {:phoenix, "~> 1.8.1"},
      {:plug, "~> 1.16"},
      {:req, "~> 0.5.15"},
      {:gnat, "~> 1.11.1"},
      {:jetstream, "~> 0.0.9"},
      {:jetstream_setup, path: "../../libs/jetstream_setup"},
      {:broadway, "~> 1.2"},
      # serializers
      {:jason, "~> 1.4"},
      {:protos, path: "../../libs/protos"},
      {:protobuf, "~> 0.15.0"},
      {:otel_nats, path: "../../libs/otel_nats"},
      # process runner
      {:ex_cmd, "~> 0.16.0"},

      # OpenTelemetry for distributed tracing (exporter MUST be before opentelemetry)
      {:opentelemetry, "~> 1.7"},
      {:opentelemetry_api, "~> 1.5"},
      {:opentelemetry_req, "~> 1.0"},
      {:opentelemetry_ecto, "~> 1.2"},
      {:opentelemetry_phoenix, "~> 2.0"},
      {:opentelemetry_bandit, "~> 0.3.0"},
      {:opentelemetry_exporter, "~> 1.10"},
      {:opentelemetry_logger_metadata, "~> 0.2.0"},
      {:tls_certificate_check, "~> 1.29"},

      # Prometheus metrics
      {:prom_ex, "~> 1.11.0"},
      {:telemetry_metrics_prometheus_core, "~> 1.2"},
      {:telemetry_poller, "~> 1.3"},

      # Structured JSON logging
      {:logger_json, "~> 7.0"},
      {:ex_aws, "~> 2.6"},
      {:ex_aws_s3, "~> 2.5.8"},
      {:hackney, "~> 1.20"},
      {:sweet_xml, "~> 0.7.5"},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false}
    ]
  end
end
