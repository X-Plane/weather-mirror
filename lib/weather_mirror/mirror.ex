defmodule WeatherMirror.Mirror do
  @moduledoc "Utilities for mirroring live URLs"
  import ExPrintf
  require Logger

  def mirror_url(conn, cache_key, url_generator, send_resp, merge_resp_headers) do
    soft_invalidate_mins = min(15, mins_until_next_hour())
    url = url_generator.(DateTime.utc_now())

    case get_or_update_cached_data(cache_key, url, soft_invalidate_mins) do
      {:error, status_code, msg} ->
        send_resp.(conn, status_code, msg)

      {_, %HTTPoison.Response{status_code: status, headers: headers, body: body}} ->
        conn
        |> merge_resp_headers.(header_keys_lowercase(headers))
        |> send_resp.(status, body)

      _ ->
        send_resp.(conn, 500, "An unknown error occurred")
    end
  end

  # NOAA sends headers with keys like "Date" and "Content-Type", but HTTPoison asserts keys have to be all lowercase
  defp header_keys_lowercase(headers), do: Enum.map(headers, fn {k, v} -> {String.downcase(k), v} end)

  def mins_until_next_hour, do: 60 - DateTime.utc_now().minute

  defp get_or_update_cached_data(cache_key, url, soft_invalidate_mins) do
    case WeatherMirror.Cache.lookup(cache_key) do
      {:ok, content} ->
        {:ok, content}

      {:soft_invalidated, content} ->
        proxy_live_url(cache_key, url, soft_invalidate_mins, content)

      _ ->
        proxy_live_url(cache_key, url, soft_invalidate_mins)
    end
  end

  # Returns one of:
  # {:ok, HTTPoison.Response}
  # {:error, status_code, error_message}
  defp proxy_live_url(cache_key, url, soft_invalidate_mins, fallback_response \\ nil) do
    case HTTPoison.get(url) do
      {:ok, response = %HTTPoison.Response{status_code: status}} when status in 200..299 ->
        WeatherMirror.Cache.put(cache_key, response, soft_invalidate_mins)
        {:ok, response}

      {:ok, _} when fallback_response ->
        {:ok, fallback_response}

      {:ok, %HTTPoison.Response{status_code: err_status}} ->
        {:error, err_status, "Weather data unavailable"}

      error ->
        if fallback_response do
          {:ok, fallback_response}
        else
          Logger.error("Totally failed to fetch weather data from #{url}\n#{inspect(error)}")
          {:error, 500, "Failed to fetch weather data"}
        end
    end
  end

  def get_date_params(utc_date) do
    four_hours_ago = DateTime.add(utc_date, -4 * 60 * 60, :second)
    cycle = div(four_hours_ago.hour, 6) * 6
    adjustment = if utc_date.day == four_hours_ago.day, do: 0, else: 24

    %{
      date_cycle: sprintf("%d%02d%02d", [four_hours_ago.year, four_hours_ago.month, four_hours_ago.day]),
      forecast: div(adjustment + utc_date.hour - cycle, 3) * 3,
      cycle: cycle
    }
  end
end
