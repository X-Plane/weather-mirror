defmodule WeatherMirror.Endpoint do
  use Plug.Router
  alias WeatherMirror.NoaaDate
  import ExPrintf
  import WeatherMirror.Mirror, only: [mirror_url: 5]

  @listen_on_port 4001

  plug(:match)
  plug(:dispatch)

  get("/metar/", do: mirror_url(conn, "metar", &metar_url/1, &send_resp/3, &merge_resp_headers/2))
  get("/wafs/", do: mirror_url(conn, "wafs", &wafs_url/1, &send_resp/3, &merge_resp_headers/2))
  get("/gfs/", do: mirror_url(conn, "gfs", &gfs_url/1, &send_resp/3, &merge_resp_headers/2))

  match _ do
    send_resp(conn, 404, "Requested page not found.")
  end

  def metar_url(%DateTime{} = utc_date) do
    # 1 hour in the past because the current hour at NOAA is always 0 bytes
    prev_hour = rem(23 + utc_date.hour, 24)
    sprintf("https://tgftp.nws.noaa.gov/data/observations/metar/cycles/%02dZ.TXT", [prev_hour])
  end

  def wafs_url(%DateTime{} = utc_date) do
    date_params = NoaaDate.from_utc(utc_date)

    sprintf(
      "https://www.ftp.ncep.noaa.gov/data/nccf/com/gfs/prod/gfs.%s/%02d/WAFS_blended_%s%02df%02d.grib2",
      [
        date_params.date_cycle,
        date_params.cycle,
        date_params.date_cycle,
        date_params.cycle,
        # Magic constants! What do they do? Why do we make the min forecast param 6 here? Who knows!
        # But this matches what we previously received from the dev who integrated global winds with X-Plane... :(
        if(date_params.forecast < 6, do: 6, else: date_params.forecast)
      ]
    )
  end

  def gfs_url(%DateTime{} = utc_date) do
    date_params = NoaaDate.from_utc(utc_date)

    base_url =
      sprintf(
        "https://nomads.ncep.noaa.gov/cgi-bin/filter_gfs_1p00.pl?dir=%%2Fgfs.%s/%02d&file=gfs.t%02dz.pgrb2.1p00.f0%02d",
        [
          date_params.date_cycle,
          date_params.cycle,
          date_params.cycle,
          date_params.forecast
        ]
      )

    # Request lev_700_mb => 9,878 and lev_250_mb => 33,985 ft
    # Request U and V vectors for wind direction
    base_url <> "&lev_700_mb=1&lev_250_mb=1" <> "&var_UGRD=1&var_VGRD=1"
  end

  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]}
    }
  end

  def start_link(_opts) do
    Plug.Cowboy.http(__MODULE__, [],
      port: @listen_on_port,
      stream_handlers: [:cowboy_compress_h, WeatherMirror.StripTransferEncoding, :cowboy_stream_h]
    )
  end
end
