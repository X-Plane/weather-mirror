defmodule WeatherMirror.EndpointTest do
  use ExUnit.Case, async: true

  test "parses dates into the components NOAA uses" do
    times = times_of_day()

    assert %{
             date_cycle: "20190211",
             cycle: 18,
             forecast: 3
           } == WeatherMirror.Endpoint.get_date_params(times[:late])

    assert %{
             date_cycle: "20190212",
             cycle: 18,
             forecast: 6
           } == WeatherMirror.Endpoint.get_date_params(times[:early])

    assert %{
             date_cycle: "20190212",
             cycle: 12,
             forecast: 3
           } == WeatherMirror.Endpoint.get_date_params(times[:mid])
  end

  test "generates GFS URLs" do
    times = times_of_day()

    assert WeatherMirror.Endpoint.gfs_url(times[:late]) ==
             "https://nomads.ncep.noaa.gov/cgi-bin/filter_gfs_1p00.pl?dir=%2Fgfs.20190211/18&file=gfs.t18z.pgrb2.1p00.f003&lev_700_mb=1&lev_250_mb=1&var_UGRD=1&var_VGRD=1"

    assert WeatherMirror.Endpoint.gfs_url(times[:early]) ==
             "https://nomads.ncep.noaa.gov/cgi-bin/filter_gfs_1p00.pl?dir=%2Fgfs.20190212/18&file=gfs.t18z.pgrb2.1p00.f006&lev_700_mb=1&lev_250_mb=1&var_UGRD=1&var_VGRD=1"

    assert WeatherMirror.Endpoint.gfs_url(times[:mid]) ==
             "https://nomads.ncep.noaa.gov/cgi-bin/filter_gfs_1p00.pl?dir=%2Fgfs.20190212/12&file=gfs.t12z.pgrb2.1p00.f003&lev_700_mb=1&lev_250_mb=1&var_UGRD=1&var_VGRD=1"
  end

  test "generates WAFS URLs" do
    times = times_of_day()

    assert WeatherMirror.Endpoint.wafs_url(times[:late]) ==
             "https://www.ftp.ncep.noaa.gov/data/nccf/com/gfs/prod/gfs.20190211/18/WAFS_blended_2019021118f06.grib2"

    assert WeatherMirror.Endpoint.wafs_url(times[:early]) ==
             "https://www.ftp.ncep.noaa.gov/data/nccf/com/gfs/prod/gfs.20190212/18/WAFS_blended_2019021218f06.grib2"

    assert WeatherMirror.Endpoint.wafs_url(times[:mid]) ==
             "https://www.ftp.ncep.noaa.gov/data/nccf/com/gfs/prod/gfs.20190212/12/WAFS_blended_2019021212f06.grib2"
  end

  test "generates METAR URLs" do
    test_date = DateTime.from_unix!(1_550_019_493)

    assert WeatherMirror.Endpoint.metar_url(test_date) ==
             "https://tgftp.nws.noaa.gov/data/observations/metar/cycles/23Z.TXT"
  end

  def times_of_day do
    %{
      # 2019-02-11 22:14Z
      late: DateTime.from_unix!(1_549_923_284),
      # 2019-02-13 02:37Z --- 6 hours ago will cross the date boundary
      early: DateTime.from_unix!(1_550_025_476),
      # 2019-02-12 17:32Z
      mid: DateTime.from_unix!(1_549_992_766)
    }
  end
end
