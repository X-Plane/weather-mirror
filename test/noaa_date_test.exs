defmodule WeatherMirror.NoaaDateTest do
  alias WeatherMirror.NoaaDate
  use ExUnit.Case, async: true

  test "parses dates into the components NOAA uses" do
    # 2019-02-11 22:14Z
    late = DateTime.from_unix!(1_549_923_284)
    # 2019-02-13 02:37Z --- 6 hours ago will cross the date boundary
    early = DateTime.from_unix!(1_550_025_476)
    # 2019-02-12 17:32Z
    mid = DateTime.from_unix!(1_549_992_766)

    assert %NoaaDate{date_cycle: "20190212", cycle: 18, forecast: 6} == NoaaDate.from_utc(early)
    assert %NoaaDate{date_cycle: "20190212", cycle: 12, forecast: 3} == NoaaDate.from_utc(mid)
    assert %NoaaDate{date_cycle: "20190211", cycle: 18, forecast: 3} == NoaaDate.from_utc(late)
  end
end
