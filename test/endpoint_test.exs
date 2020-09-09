defmodule WeatherMirror.EndpointTest do
  use ExUnit.Case, async: true
  use Plug.Test
  require Logger
  import WeatherMirror.Endpoint, only: [gfs_url: 1, wafs_url: 1, metar_url: 1]

  # 2019-02-11 22:14Z
  @late DateTime.from_unix!(1_549_923_284)
  # 2019-02-13 02:37Z --- 6 hours ago will cross the date boundary
  @early DateTime.from_unix!(1_550_025_476)
  # 2019-02-12 17:32Z
  @mid DateTime.from_unix!(1_549_992_766)
  @now DateTime.utc_now()

  test "generates GFS URLs" do
    assert gfs_url(@late) ==
             "https://nomads.ncep.noaa.gov/cgi-bin/filter_gfs_1p00.pl?dir=%2Fgfs.20190211/18&file=gfs.t18z.pgrb2.1p00.f003&lev_700_mb=1&lev_250_mb=1&var_UGRD=1&var_VGRD=1"

    assert gfs_url(@early) ==
             "https://nomads.ncep.noaa.gov/cgi-bin/filter_gfs_1p00.pl?dir=%2Fgfs.20190212/18&file=gfs.t18z.pgrb2.1p00.f006&lev_700_mb=1&lev_250_mb=1&var_UGRD=1&var_VGRD=1"

    assert gfs_url(@mid) ==
             "https://nomads.ncep.noaa.gov/cgi-bin/filter_gfs_1p00.pl?dir=%2Fgfs.20190212/12&file=gfs.t12z.pgrb2.1p00.f003&lev_700_mb=1&lev_250_mb=1&var_UGRD=1&var_VGRD=1"
  end

  test "generates WAFS URLs" do
    assert wafs_url(@late) ==
             "https://www.ftp.ncep.noaa.gov/data/nccf/com/gfs/prod/gfs.20190211/18/WAFS_blended_2019021118f06.grib2"

    assert wafs_url(@early) ==
             "https://www.ftp.ncep.noaa.gov/data/nccf/com/gfs/prod/gfs.20190212/18/WAFS_blended_2019021218f06.grib2"

    assert wafs_url(@mid) ==
             "https://www.ftp.ncep.noaa.gov/data/nccf/com/gfs/prod/gfs.20190212/12/WAFS_blended_2019021212f06.grib2"
  end

  test "generates METAR URLs" do
    test_date = DateTime.from_unix!(1_550_019_493)

    assert metar_url(test_date) ==
             "https://tgftp.nws.noaa.gov/data/observations/metar/cycles/23Z.TXT"
  end

  test "end to end" do
    assert status("/metar/") == 200 || live_url_is_dead(metar_url(@now))
    assert status("/gfs/") == 200 || live_url_is_dead(gfs_url(@now))
    assert status("/wafs/") == 200 || live_url_is_dead(wafs_url(@now))
  end

  defp status(endpoint_path) do
    response = WeatherMirror.Endpoint.call(conn(:get, endpoint_path), WeatherMirror.Endpoint.init([]))

    if response.status >= 400 do
      Logger.error("failing response body:\n#{inspect(response.resp_body, limit: :infinity)}")
    end

    response.status
  end

  defp live_url_is_dead(noaa_url) do
    HTTPoison.get(noaa_url).status >= 400
  end
end
