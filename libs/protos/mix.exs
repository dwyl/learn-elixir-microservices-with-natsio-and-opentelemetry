defmodule Protos.MixProject do
  use Mix.Project

  def project do
    [
      app: :protos,
      version: "0.1.0",
      elixir: "~> 1.19",
      elixirc_paths: elixirc_paths(Mix.env()),
      compilers: Mix.compilers() ++ [:proto_compiler],
      deps: deps(),
      # Proto compiler config
      proto_compiler: [
        source_dir: "proto_defs/#{protos_version()}",
        output_dir: "lib/protos/#{protos_version()}"
      ]
    ]
  end

  defp protos_version, do: "V3"

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Specifies which paths to compile per environment
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:protobuf, "~> 0.15.0"}
    ]
  end
end
