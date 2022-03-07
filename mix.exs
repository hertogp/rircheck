defmodule Rircheck.MixProject do
  use Mix.Project

  @source_url "https://github.com/hertogp/rircheck"
  @version "0.1.0"

  def project do
    [
      app: :rircheck,
      version: @version,
      name: "Rircheck",
      description: "cli tool to examine and debug ASN registrations",
      aliases: [docs: ["docs"]],
      elixir: "~> 1.13",
      start_permanent: Mix.env() == :prod,
      docs: docs(),
      deps: deps(),
      escript: [main_module: Rircheck]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: []
    ]
  end

  defp docs() do
    [
      extras: [
        "CHANGELOG.md": [],
        "LICENSE.md": [title: "License"],
        "README.md": [title: "Overview"]
      ],
      main: "readme",
      source_url: @source_url,
      source_ref: "v#{@version}",
      assets: "assets",
      formatters: ["html"]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:httpoison, "~> 1.7"},
      {:jason, "~> 1.2"},
      {:iptrie, "~> 0.8"},
      {:ex_doc, "~> 0.24", only: :dev, runtime: false},
      {:dialyxir, "~> 1.0", only: :dev, runtime: false},
      {:credo, "~> 1.6", only: [:dev, :test], runtime: false}
    ]
  end
end
