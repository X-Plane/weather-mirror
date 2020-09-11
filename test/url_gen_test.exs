defmodule WeatherMirror.UrlGenTest do
  use ExUnit.Case, async: true
  import WeatherMirror.UrlGen, only: [gfs: 1, wafs: 1, metar: 1]

  # 2019-02-13 02:37Z --- 6 hours ago will cross the date boundary
  @early DateTime.from_unix!(1_550_025_476)
  # 2019-02-12 17:32Z
  @mid DateTime.from_unix!(1_549_992_766)
  # 2019-02-11 22:14Z
  @late DateTime.from_unix!(1_549_923_284)

  test "generates GFS URLs" do
    gfs_base = "https://nomads.ncep.noaa.gov/cgi-bin/filter_gfs_1p00.pl"
    assert gfs(@early) == "#{gfs_base}?dir=%2Fgfs.20190212/18&file=gfs.t18z.pgrb2.1p00.f006&lev_700_mb=1&lev_250_mb=1&var_UGRD=1&var_VGRD=1"
    assert gfs(@mid) == "#{gfs_base}?dir=%2Fgfs.20190212/12&file=gfs.t12z.pgrb2.1p00.f003&lev_700_mb=1&lev_250_mb=1&var_UGRD=1&var_VGRD=1"
    assert gfs(@late) == "#{gfs_base}?dir=%2Fgfs.20190211/18&file=gfs.t18z.pgrb2.1p00.f003&lev_700_mb=1&lev_250_mb=1&var_UGRD=1&var_VGRD=1"
  end

  test "generates WAFS URLs" do
    assert wafs(@early) == "https://www.ftp.ncep.noaa.gov/data/nccf/com/gfs/prod/gfs.20190212/18/WAFS_blended_2019021218f06.grib2"
    assert wafs(@mid) == "https://www.ftp.ncep.noaa.gov/data/nccf/com/gfs/prod/gfs.20190212/12/WAFS_blended_2019021212f06.grib2"
    assert wafs(@late) == "https://www.ftp.ncep.noaa.gov/data/nccf/com/gfs/prod/gfs.20190211/18/WAFS_blended_2019021118f06.grib2"
  end

  test "generates METAR URLs" do
    test_date = DateTime.from_unix!(1_550_019_493)
    assert metar(test_date) == "https://tgftp.nws.noaa.gov/data/observations/metar/cycles/23Z.TXT"
  end
end
