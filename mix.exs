defmodule WeatherMirror.MixProject do
  use Mix.Project

  def project do
    [
      app: :weather_mirror,
      version: "0.1.0",
      elixir: "~> 1.9",
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
      {:plug, "~> 1.8.3"},
      {:cowboy, "~> 2.7"},
      {:plug_cowboy, "~> 2.0"},
      {:exprintf, "~> 0.2.1"},
      {:httpoison, "~> 1.6"},
      {:credo, "~> 1.1.0", only: [:dev, :test], runtime: false}
    ]
  end
end
