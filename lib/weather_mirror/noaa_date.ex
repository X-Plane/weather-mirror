defmodule WeatherMirror.NoaaDate do
  @moduledoc "A struct to represent the parameters that NOAA URLs all use"
  import ExPrintf

  @enforce_keys [:date_cycle, :forecast, :cycle]
  defstruct date_cycle: "", forecast: 0, cycle: 0

  def from_utc(%DateTime{} = utc_date) do
    four_hours_ago = DateTime.add(utc_date, -4 * 60 * 60, :second)
    cycle = div(four_hours_ago.hour, 6) * 6
    adjustment = if utc_date.day == four_hours_ago.day, do: 0, else: 24

    %WeatherMirror.NoaaDate{
      date_cycle: sprintf("%d%02d%02d", [four_hours_ago.year, four_hours_ago.month, four_hours_ago.day]),
      forecast: div(adjustment + utc_date.hour - cycle, 3) * 3,
      cycle: cycle
    }
  end
end
