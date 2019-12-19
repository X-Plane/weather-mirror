defmodule WeatherMirror.Application do
  @moduledoc """
  Starts monitored endpoints for caching specific NOAA data
  """
  use Application

  def start(_type, _args) do
    children = [
      {WeatherMirror.Cache, name: WeatherMirror.Cache},
      {WeatherMirror.Endpoint, name: WeatherMirror.Endpoint}
    ]

    opts = [strategy: :one_for_one, name: WeatherMirror.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
