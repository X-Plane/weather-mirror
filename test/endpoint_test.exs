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

  @tag e2e: true
  test "end to end" do
    Enum.each([{"/metar/", &metar_url/1}, {"/gfs/", &gfs_url/1}, {"/wafs/", &wafs_url/1}], fn {route, url_gen} ->
      if !live_url_is_dead(url_gen.(@now)) do
        %{status: status, resp_headers: headers, resp_body: _} = fetch(route)
        assert status == 200
        assert all_lowercase_headers(headers)
        refute has_cached_header(headers), "Shouldn't have this URL cached the first time"
        refute has_transfer_encoding_header(headers), "Transfer-Encoding header will break GFS downloads; headers #{inspect(headers)}"

        # Second time get the cached response
        %{status: 200, resp_headers: headers, resp_body: _} = fetch(route)
        assert all_lowercase_headers(headers)
        assert has_cached_header(headers), "Second response should have come from cache"
        refute has_transfer_encoding_header(headers), "Transfer-Encoding header will break GFS downloads; headers #{inspect(headers)}"

        {:ok, %HTTPoison.Response{status_code: 200}} = HTTPoison.head("http://localhost:#{System.get_env("PORT") || 4001}#{route}")
      end
    end)
  end

  defp fetch(route), do: WeatherMirror.Endpoint.call(conn(:get, route), WeatherMirror.Endpoint.init([]))

  defp all_lowercase_headers(headers), do: Enum.any?(headers, fn {k, _} -> k == String.downcase(k) end)
  defp has_cached_header(headers), do: Enum.any?(headers, fn {k, _} -> k == "cached-at" end)
  defp has_transfer_encoding_header(headers), do: Enum.any?(headers, fn {k, _} -> k == "transfer-encoding" end)

  defp live_url_is_dead(noaa_url) do
    case HTTPoison.head(noaa_url) do
      {:ok, %HTTPoison.Response{status_code: status}} -> status >= 400
      _ -> true
    end
  end
end
