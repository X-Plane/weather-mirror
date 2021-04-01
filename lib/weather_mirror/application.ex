defmodule WeatherMirror.Application do
  @moduledoc """
  Starts monitored endpoints for caching specific NOAA data
  """
  use Application

  @default_port 4001

  def start(_type, _args) do
    HTTPoison.start()
    {:ok, _} = Application.ensure_all_started(:appsignal)

    children = [
      {Registry, keys: :unique, name: WeatherMirror.AutoUpdatingUrlCache},
      cache_spec(:metar, &WeatherMirror.UrlGen.metar/1),
      cache_spec(:wafs, &WeatherMirror.UrlGen.wafs/1),
      cache_spec(:gfs, &WeatherMirror.UrlGen.gfs/1),
      Plug.Cowboy.child_spec(
        scheme: :http,
        plug: WeatherMirror.Endpoint,
        options: [
          port: System.get_env("PORT", "#{@default_port}") |> String.to_integer(),
          stream_handlers: [:cowboy_compress_h, :cowboy_stream_h]
        ]
      )
    ]

    opts = [strategy: :one_for_one, name: WeatherMirror.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp cache_spec(name, url_generator) when is_atom(name) and is_function(url_generator) do
    %{
      id: name,
      start: {WeatherMirror.AutoUpdatingUrlCache, :start_link, [name, url_generator]}
    }
  end
end
