defmodule WeatherMirror.MixProject do
  use Mix.Project

  def project do
    [
      app: :weather_mirror,
      version: "0.2.0",
      elixir: "~> 1.10",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger],
      mod: {WeatherMirror.Application, []}
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:plug, "~> 1.9.0"},
      {:cowboy, "~> 2.8"},
      {:plug_cowboy, "~> 2.3.0"},
      {:exprintf, "~> 0.2.1"},
      {:httpoison, "~> 1.7"},
      {:credo, "~> 1.2.3", only: [:dev, :test], runtime: false}
    ]
  end
end
