defmodule EmailSvc.MixProject do
  use Mix.Project

  def project do
    [
      app: :email_svc,
      version: "0.1.0",
      # build_path: "/_build",
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
      email_svc: [
        applications: [
          opentelemetry_exporter: :permanent,
          opentelemetry: :temporary
        ],
        # only :unix
        include_executables_for: [:unix]
      ]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [
        :logger,
        # :inets,
        :os_mon,
        :tls_certificate_check
      ],
      mod: {EmailService.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:libcluster, "~> 3.5"},
      {:phoenix, "~> 1.8.1"},
      {:req, "~> 0.5.15"},
      {:bandit, "~> 1.8"},
      {:gnat, "~> 1.11.1"},
      {:jetstream, "~> 0.0.9"},
      # email client
      {:swoosh, "~> 1.19.8"},
      # serializers
      {:jason, "~> 1.4"},
      {:protos, path: "../../libs/protos"},
      {:protobuf, "~> 0.15.0"},
      {:otel_nats, path: "../../libs/otel_nats"},

      # Telemetry, OpenTelemetry for distributed tracing
      {:telemetry, "~> 1.3"},
      {:telemetry_metrics, "~> 1.1"},
      {:opentelemetry_api, "~> 1.5"},
      {:opentelemetry_exporter, "~> 1.10"},
      {:opentelemetry, "~> 1.7"},
      {:opentelemetry_req, "~> 1.0"},
      {:opentelemetry_phoenix, "~> 2.0"},
      {:opentelemetry_bandit, "~> 0.3.0"},
      {:tls_certificate_check, "~> 1.29"},

      # Prometheus metrics
      {:prom_ex, "~> 1.11.0"},
      {:telemetry_metrics_prometheus_core, "~> 1.2"},
      {:telemetry_poller, "~> 1.3"},

      # Structured JSON logging
      {:logger_json, "~> 7.0"},

      # OpenAPI documentation
      # {:open_api_spex, "~> 3.21"},
      # inspect
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:yaml_elixir, "~> 2.12", only: :test}
    ]
  end
end
