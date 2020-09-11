defmodule WeatherMirror.UrlGen do
  @moduledoc """
  Generators for NOAA weather URLs
  """
  import ExPrintf
  alias WeatherMirror.NoaaDate

  def metar(%DateTime{} = utc_date) do
    # 1 hour in the past because the current hour at NOAA is always 0 bytes
    prev_hour = rem(23 + utc_date.hour, 24)
    sprintf("https://tgftp.nws.noaa.gov/data/observations/metar/cycles/%02dZ.TXT", [prev_hour])
  end

  def wafs(%DateTime{} = utc_date) do
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
        max(6, date_params.forecast)
      ]
    )
  end

  def gfs(%DateTime{} = utc_date) do
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
end
