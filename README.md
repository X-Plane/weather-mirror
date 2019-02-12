# weather-mirror

This is a Node.JS server used to mirror weather data used by [the X-Plane flight simulator](https://www.x-plane.com).

It serves METAR weather, as well as GRIB2 winds and turbulence data acquired from NOAA.

It caches the results in memory, so that it makes at most one successful request per hour from the NOAA servers. And, in the event that the NOAA servers go down, we'll continue serving the most recent data we have until they come back online.
