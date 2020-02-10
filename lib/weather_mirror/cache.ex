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
  Looks up the cached content `cache_key` stored in `server`.
  Returns `{:ok, content}` if the cached content exists and is fresh,
  `{:soft_invalidated, content}` if the cached content is stale (you should try to update it),
  and `:error` if we have no cached content.
  """
  def lookup(cache_key), do: GenServer.call(__MODULE__, {:lookup, cache_key})
  def lookup(cache_pid, cache_key), do: GenServer.call(cache_pid, {:lookup, cache_key})

  def put(cache_key, content, soft_invalidate_mins),
    do: GenServer.call(__MODULE__, {:put, cache_key, content, soft_invalidate_mins})

  def put(cache_pid, cache_key, content, soft_invalidate_mins),
    do: GenServer.call(cache_pid, {:put, cache_key, content, soft_invalidate_mins})

  ################ Server Implementation ################
  @impl true
  def init(:ok),
    do: {:ok, %{}}

  @impl true
  def handle_call({:lookup, cache_key}, _from, url_cache) do
    response =
      case Map.fetch(url_cache, cache_key) do
        {:ok, {content, invalidate_time}} -> {cache_status(invalidate_time), content}
        _ -> {:error}
      end

    {:reply, response, url_cache}
  end

  @impl true
  def handle_call({:put, cache_key, content, soft_invalidate_mins}, _from, url_cache) do
    inval_time = DateTime.utc_now() |> DateTime.add(soft_invalidate_mins * 60, :second)
    {:reply, :ok, Map.put(url_cache, cache_key, {content, inval_time})}
  end

  defp cache_status(invalidation_time_utc) do
    case DateTime.compare(invalidation_time_utc, DateTime.utc_now()) do
      :lt -> :soft_invalidated
      _ -> :ok
    end
  end
end
