# weather-mirror

**`main` build status**: [![main build status](https://circleci.com/gh/X-Plane/weather-mirror/tree/main.svg?style=svg)](https://circleci.com/gh/X-Plane/weather-mirror/tree/main) **Latest commit build status**: [![Last commit build status](https://circleci.com/gh/X-Plane/weather-mirror.svg?style=svg)](https://circleci.com/gh/X-Plane/weather-mirror)

This is an Elixir server used to mirror weather data used by [the X-Plane flight simulator](https://www.x-plane.com).

It serves METAR weather, as well as GRIB2 winds and turbulence data acquired from NOAA.

It caches the results in memory, so that it makes at most one successful request per hour from the NOAA servers. And, in the event that the NOAA servers go down, we'll continue serving the most recent data we have until they come back online.

You can see the three URLs it mirrors at:

- [lookup.x-plane.com/\_lookup\_11\_/weather/metar/](http://lookup.x-plane.com/_lookup_11_/weather/metar/)
- [lookup.x-plane.com/\_lookup\_11\_/weather/gfs/](http://lookup.x-plane.com/_lookup_11_/weather/gfs/)
- [lookup.x-plane.com/\_lookup\_11\_/weather/wafs/](http://lookup.x-plane.com/_lookup_11_/weather/wafs/)

## Architecture

This is a pretty simple application. The architecture, such as it is, looks like this:

- `WeatherMirror.AutoUpdatingUrlCache` is the core of the app. At startup, `WeatherMirror.Application` initializes one cache per endpoint we serve. The URL cache will try to GET the data it mirrors at startup, and forever after it will poll NOAA for new data every 30 seconds (configurable via the module attribute `@timeout_ms`).
- `WeatherMirror.Endpoint` is our router—it defines the three HTTP GET endpoints we support, and when requests come in, it asks the `WeatherMirror.AutoUpdatingUrlCache` for the latest data we have for that endpoint. 
- `WeatherMirror.UrlGen` takes a UTC `DateTime` and produces the corresponding NOAA URL for the different types of data we proxy ([METAR](https://en.wikipedia.org/wiki/METAR) for general weather conditions, and [GRIB](https://en.wikipedia.org/wiki/GRIB) + [WAFS](https://aviationweather.gov/wafs) for winds specifically). The format for these URLs is quite arcane, so it uses the `WeatherMirror.NoaaDate` module to encapsulate some of the common parameters.

## Deployment

We deploy via [Dokku](http://dokku.viewdocs.io/dokku/) (a self-hosted Heroku-like PaaS, which we run on Digital Ocean). You can Git push to `ssh://dokku@weather.x-plane.com/weather_mirror` and Dokku will handle the deploy for you (but note that Dokku uses `master`, not `main`):

    $ git remote add dokku ssh://dokku@weather.x-plane.com/weather_mirror
    $ git push dokku main:master

There's one *terribly* frustrating aspect of deployment: as part of our zero-downtime checks (see the `CHECKS` file in the project root), we test that the newly spun-up server actually has data for all three endpoints. Seems simple, but you would be *amazed* at how many times I have to retry this due to NOAA not being able to return an HTTP 200. In the past, I've had to retry this a dozen times before I could get an HTTP 200 on all three at the same time. (Did I mention how unreliable X-Plane's weather data was before we had a caching proxy in front of NOAA?)

There's a (theoretically) simple to-do here for the future: When the app is starting up, if NOAA is down, we should just try to fetch the data from the *currently*-running X-Plane weather server—that is, instead of fetching from noaa.gov to initialize, we should talk to weather.x-plane.com.

## Testing

[We use CircleCI](https://app.circleci.com/pipelines/github/X-Plane/weather-mirror) to run the test suite on every commit.

You can run the same tests that CircleCI does by doing `$ ./git-pre-commit-hook.sh`. (I recommend you make this your pre-commit hook as well, of course.)

That script will:

1. Run the Credo linter: `$ mix credo --strict`
2. Confirm the code matches the official formatter: `$ mix format --check-formatted`
3. Confirm the tests pass: `$ mix test` (or if you like more verbose output, `$ mix test --trace`)
