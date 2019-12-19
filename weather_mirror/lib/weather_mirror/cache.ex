defmodule WeatherMirror.Cache do
  @moduledoc """
  Stores data for a URL and retrieves it later.
  Things never actually get deleted from the cache... instead we return a "soft invalidate" message,
  politely suggesting that clients should try to grab a more fresh copy.
  """
  use GenServer

  def start_link(opts),
    do: GenServer.start_link(__MODULE__, :ok, opts)

  @doc """
  Looks up the cached content `url` stored in `server`.
  Returns `{:ok, content}` if the cached content exists and is fresh,
  `{:soft_invalidated, content}` if the cached content is stale (you should try to update it),
  and `:error` if we have no cached content.
  """
  def lookup(cache_server, url),
    do: GenServer.call(cache_server, {:lookup, url})

  def put(cache_server, url, content, soft_invalidate_mins),
    do: GenServer.call(cache_server, {:put, url, content, soft_invalidate_mins})

  ################ Server Implementation ################
  @impl true
  def init(:ok),
    do: {:ok, %{}}

  @impl true
  def handle_call({:lookup, url}, _from, url_cache) do
    response =
      case Map.fetch(url_cache, url) do
        {:ok, {content, invalidate_time}} -> {cache_status(invalidate_time), content}
        _ -> {:error}
      end

    {:reply, response, url_cache}
  end

  @impl true
  def handle_call({:put, url, content, soft_invalidate_mins}, _from, url_cache) do
    inval_time = DateTime.utc_now() |> DateTime.add(soft_invalidate_mins * 60, :second)
    {:reply, :ok, Map.put(url_cache, url, {content, inval_time})}
  end

  defp cache_status(invalidation_time_utc) do
    case DateTime.compare(invalidation_time_utc, DateTime.utc_now()) do
      :lt -> :soft_invalidated
      _ -> :ok
    end
  end
end
