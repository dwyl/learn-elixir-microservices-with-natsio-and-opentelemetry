defmodule JetstreamSetup.MixProject do
  use Mix.Project

  def project do
    [
      app: :jetstream_setup,
      version: "0.1.0",
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [extra_applications: [:logger]]
  end

  defp deps do
    [
      {:jetstream, "~> 0.0.9"}
    ]
  end
end
