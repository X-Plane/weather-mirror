defmodule WeatherMirror.Endpoint do
  use Plug.Router

  plug(Plug.Head)
  plug(:match)
  plug(:dispatch)

  get("/metar/", do: mirror_url(conn, :metar))
  get("/wafs/", do: mirror_url(conn, :wafs))
  get("/gfs/", do: mirror_url(conn, :gfs))

  match(_, do: send_resp(conn, 404, "Requested page not found."))

  defp mirror_url(conn, cache_id) do
    case WeatherMirror.AutoUpdatingUrlCache.get(cache_id) do
      %HTTPoison.Response{} = response -> send_cached(conn, response)
      :error -> send_resp(conn, 404, "The server does not yet have this data.")
      _ -> send_resp(conn, 500, "An unknown error occurred")
    end
  end

  defp send_cached(conn, %HTTPoison.Response{status_code: status, headers: headers, body: body}) do
    conn
    |> merge_resp_headers(headers)
    |> send_resp(status, body)
  end
end
