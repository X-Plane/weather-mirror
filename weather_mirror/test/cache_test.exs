defmodule WeatherMirror.CacheTest do
  use ExUnit.Case, async: true

  setup do
    %{cache: start_supervised!(WeatherMirror.Cache)}
  end

  test "looks up arbitrary cached data", %{cache: cache} do
    assert {:error} = WeatherMirror.Cache.lookup(cache, "foo")
    WeatherMirror.Cache.put(cache, "foo", "bar", 15)
    assert {:ok, "bar"} = WeatherMirror.Cache.lookup(cache, "foo")

    assert {:error} = WeatherMirror.Cache.lookup(cache, "baz")
    WeatherMirror.Cache.put(cache, "baz", [1, 2, 3], 15)
    assert {:ok, [1, 2, 3]} = WeatherMirror.Cache.lookup(cache, "baz")
  end

  test "invalidates caches", %{cache: cache} do
    assert {:error} = WeatherMirror.Cache.lookup(cache, "bang")
    WeatherMirror.Cache.put(cache, "bang", "bop", -1)
    assert {:soft_invalidated, "bop"} = WeatherMirror.Cache.lookup(cache, "bang")
  end

  test "can revalidate cache", %{cache: cache} do
    assert {:error} = WeatherMirror.Cache.lookup(cache, "revalidate")
    WeatherMirror.Cache.put(cache, "revalidate", "invalidated", -1)
    assert {:soft_invalidated, "invalidated"} = WeatherMirror.Cache.lookup(cache, "revalidate")

    WeatherMirror.Cache.put(cache, "revalidate", "valid", 15)
    assert {:ok, "valid"} = WeatherMirror.Cache.lookup(cache, "revalidate")
  end
end
