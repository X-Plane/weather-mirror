defmodule WeatherMirror.EndpointTest do
  use ExUnit.Case, async: true
  use Plug.Test
  require Logger
  import WeatherMirror.UrlGen, only: [gfs: 1, wafs: 1, metar: 1]

  @tag e2e: true
  test "end to end" do
    Enum.each([{"/metar/", &metar/1}, {"/gfs/", &gfs/1}, {"/wafs/", &wafs/1}], fn {route, url_gen} ->
      if !live_url_is_dead(url_gen.(DateTime.utc_now())) do
        %{status: status, resp_headers: headers, resp_body: _} = fetch(route)
        assert status == 200
        assert all_lowercase_headers?(headers)
        refute has_transfer_encoding_header?(headers), "Transfer-Encoding header will break GFS downloads; headers #{inspect(headers)}"
        cache_timestamp1 = cached_at(headers)

        %{status: 200, resp_headers: headers, resp_body: _} = fetch(route)
        assert all_lowercase_headers?(headers)
        refute has_transfer_encoding_header?(headers), "Transfer-Encoding header will break GFS downloads; headers #{inspect(headers)}"
        cache_timestamp2 = cached_at(headers)
        assert cache_timestamp1 == cache_timestamp2

        # Third time the cache time should match the second
        %{status: 200, resp_headers: headers, resp_body: _} = fetch(route)
        assert cached_at(headers) == cache_timestamp1

        {:ok, %HTTPoison.Response{status_code: 200}} = HTTPoison.head("http://localhost:#{System.get_env("PORT") || 4001}#{route}")
      end
    end)
  end

  defp fetch(route), do: WeatherMirror.Endpoint.call(conn(:get, route), WeatherMirror.Endpoint.init([]))

  defp all_lowercase_headers?(headers), do: Enum.any?(headers, fn {k, _} -> k == String.downcase(k) end)
  defp cached_at(headers), do: headers |> Enum.find(fn {k, _} -> k == "cached-at" end) |> elem(1)
  defp has_transfer_encoding_header?(headers), do: Enum.any?(headers, fn {k, _} -> k == "transfer-encoding" end)

  defp live_url_is_dead(noaa_url) do
    case HTTPoison.head(noaa_url) do
      {:ok, %HTTPoison.Response{status_code: status}} -> status >= 400
      _ -> true
    end
  end
end
