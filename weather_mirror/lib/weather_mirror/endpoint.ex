defmodule WeatherMirror.Endpoint do
  use Plug.Router
  import ExPrintf

  plug(:match)
  plug(:dispatch)

  get("/metar/", do: mirror_url(conn, &metar_url/1))
  get("/wafs/", do: mirror_url(conn, &wafs_url/1))
  get("/gfs/", do: mirror_url(conn, &gfs_url/1))

  match _ do
    send_resp(conn, 404, "Requested page not found.")
  end

  defp mirror_url(conn, url_generator) do
    soft_invalidate_mins = min(15, mins_until_next_hour())
    url = url_generator.(DateTime.utc_now())

    case get_or_update_cached_data(url, soft_invalidate_mins) do
      {:error, status_code, msg} ->
        send_resp(conn, status_code, msg)

      {_, %HTTPoison.Response{status_code: status, headers: headers, body: body}} ->
        conn
        |> merge_resp_headers(headers)
        |> send_resp(status, body)

      _ ->
        send_resp(conn, 500, "An unknown error occurred")
    end
  end

  defp mins_until_next_hour,
    do: 60 - DateTime.utc_now().minute

  defp get_or_update_cached_data(url, soft_invalidate_mins) do
    case WeatherMirror.Cache.lookup(WeatherMirror.Cache, url) do
      {:ok, content} -> {:ok, content}
      {:soft_invalidated, content} -> proxy_live_url(url, soft_invalidate_mins, content)
      _ -> proxy_live_url(url, soft_invalidate_mins)
    end
  end

  # Returns one of:
  # {:ok, HTTPoison.Response}
  # {:error, status_code, error_message}
  defp proxy_live_url(url, soft_invalidate_mins, fallback_response \\ nil) do
    case HTTPoison.get(url) do
      {:ok, response = %HTTPoison.Response{status_code: status}} when status in 200..299 ->
        WeatherMirror.Cache.put(WeatherMirror.Cache, url, response, soft_invalidate_mins)
        {:ok, response}

      {:ok, _} when fallback_response ->
        {:ok, fallback_response}

      {:ok, %HTTPoison.Response{status_code: err_status}} ->
        {:error, err_status, "Weather data unavailable"}

      _ ->
        {:error, 500, "Failed to fetch weather data"}
    end
  end

  def metar_url(utc_date) do
    # 1 hour in the past because the current hour at NOAA is always 0 bytes
    prev_hour = rem(23 + utc_date.hour, 24)
    sprintf("https://tgftp.nws.noaa.gov/data/observations/metar/cycles/%02dZ.TXT", [prev_hour])
  end

  def wafs_url(utc_date) do
    date_params = get_date_params(utc_date)

    sprintf(
      "https://www.ftp.ncep.noaa.gov/data/nccf/com/gfs/prod/gfs.%s/%02d/WAFS_blended_%s%02df%02d.grib2",
      [
        date_params[:date_cycle],
        date_params[:cycle],
        date_params[:date_cycle],
        date_params[:cycle],
        # Magic constants! What do they do? Why do we make the min forecast param 6 here? Who knows!
        # But this matches what we previously received from the dev who integrated global winds with X-Plane... :(
        if(date_params[:forecast] < 6, do: 6, else: date_params[:forecast])
      ]
    )
  end

  def gfs_url(utc_date) do
    date_params = get_date_params(utc_date)

    base_url =
      sprintf(
        "https://nomads.ncep.noaa.gov/cgi-bin/filter_gfs_1p00.pl?dir=%%2Fgfs.%s/%02d&file=gfs.t%02dz.pgrb2.1p00.f0%02d",
        [
          date_params[:date_cycle],
          date_params[:cycle],
          date_params[:cycle],
          date_params[:forecast]
        ]
      )

    # Request lev_700_mb => 9,878 and lev_250_mb => 33,985 ft
    # Request U and V vectors for wind direction
    base_url <> "&lev_700_mb=1&lev_250_mb=1" <> "&var_UGRD=1&var_VGRD=1"
  end

  def get_date_params(utc_date) do
    four_hours_ago = DateTime.add(utc_date, -4 * 60 * 60, :second)
    cycle = div(four_hours_ago.hour, 6) * 6
    adjustment = if utc_date.day == four_hours_ago.day, do: 0, else: 24

    %{
      date_cycle:
        sprintf("%d%02d%02d", [four_hours_ago.year, four_hours_ago.month, four_hours_ago.day]),
      forecast: div(adjustment + utc_date.hour - cycle, 3) * 3,
      cycle: cycle
    }
  end

  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]}
    }
  end

  def start_link(_opts) do
    HTTPoison.start()

    Plug.Cowboy.http(__MODULE__, [],
      port: 4001,
      stream_handlers: [:cowboy_compress_h, WeatherMirror.StripTransferEncoding, :cowboy_stream_h]
    )
  end
end
