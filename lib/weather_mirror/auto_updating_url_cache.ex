defmodule WeatherMirror.AutoUpdatingUrlCache do
  @moduledoc """
  Regularly tries to fetch the latest data from a URL.
  Things never actually get deleted from the cache...
  Instead we just keep trying to update them in the background.
  """
  use GenServer

  def start_link(name, url_generator, update_ms \\ 3 * 60_000)
      when is_atom(name) and is_function(url_generator) and is_integer(update_ms) do
    GenServer.start_link(__MODULE__, {url_generator, update_ms}, name: via_tuple(name))
  end

  @doc """
  Looks up the server's latest cached content.
  Returns `HTTPoison.Response{}` if we have any cached content, or `:error` if we have no cached content.
  """
  def get(cache_pid) when is_pid(cache_pid), do: GenServer.call(cache_pid, :lookup)
  def get(cache_name) when is_atom(cache_name), do: GenServer.call(via_tuple(cache_name), :lookup)

  ################ Server Implementation ################
  @impl GenServer
  def init({url_generator, update_ms}) when is_function(url_generator) and is_integer(update_ms) do
    {:ok, update({url_generator, update_ms, nil})}
  end

  @impl GenServer
  def handle_call(:lookup, _from, {_, _, %HTTPoison.Response{} = content} = state) do
    {:reply, content, state}
  end

  @impl GenServer
  def handle_call(:lookup, _from, state) do
    {:reply, :error, state}
  end

  @impl GenServer
  def handle_info(:update, {_url_generator, _update_ms, _content} = state) do
    {:noreply, update(state)}
  end

  defp update({url_generator, update_ms, prev_content} = _state) do
    url = url_generator.(DateTime.utc_now())
    updated_content = update(url, prev_content)
    {:ok, _timer_id} = :timer.send_after(update_ms, :update)
    {url_generator, update_ms, updated_content}
  end

  defp update(url, prev_response \\ nil) when is_bitstring(url) do
    case HTTPoison.get(url, [], follow_redirect: true, recv_timeout: 15_000) do
      {:ok, %HTTPoison.Response{status_code: status} = response} when status < 300 ->
        response
        |> header_keys_lowercase()
        |> strip_unwanted_noaa_headers()
        |> add_cached_header()

      _ ->
        prev_response
    end
  end

  # NOAA sends headers with keys like "Date" and "Content-Type", but HTTPoison asserts keys have to be all lowercase
  defp header_keys_lowercase(%HTTPoison.Response{headers: headers} = response) do
    %{response | headers: Enum.map(headers, fn {k, v} -> {String.downcase(k), v} end)}
  end

  defp strip_unwanted_noaa_headers(%HTTPoison.Response{headers: headers} = response) do
    %{response | headers: strip_unwanted_noaa_headers(headers)}
  end

  defp strip_unwanted_noaa_headers(headers) when is_list(headers) do
    unwanted = ["transfer-encoding", "strict-transport-security"]
    want_header = fn {k, _v} -> !Enum.member?(unwanted, k) end
    Enum.filter(headers, want_header)
  end

  defp add_cached_header(%HTTPoison.Response{headers: headers} = response) do
    %{response | headers: [{"cached-at", DateTime.to_iso8601(DateTime.utc_now())} | headers]}
  end

  defp via_tuple(name) when is_atom(name), do: {:via, Registry, {__MODULE__, name}}
end