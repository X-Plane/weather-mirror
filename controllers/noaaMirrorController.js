(function(noaaMirrorCtrl) {
    const logger = require('../utils/logger');
    const useHttps = true;
    const http = useHttps ? require('https') : require('http');
    const cache = require('memory-cache');
    const sprintf  = require('sprintf-js').sprintf;

    noaaMirrorCtrl.init = function(app) {
        function defineGetRoute(urlToHandle, callback) {
            app.get(urlToHandle, function(req, res) {
                try {
                    callback(req, res);
                } catch(err) {
                    logger.error(urlToHandle + " - uncaught exception", err);
                    res.send(500, "An unknown error occurred");
                }
            });
        }

        defineGetRoute('/metar/:filename', noaaMirrorCtrl.metar);
        defineGetRoute('/gfs/', noaaMirrorCtrl.gfs);
        defineGetRoute('/wafs/', noaaMirrorCtrl.wafs);
    };

    /**
     * Serves the METAR file from either our in-memory cache or by forwarding on the response from the NOAA server.
     */
    noaaMirrorCtrl.metar = function(req, res) {
        const metarUrl = "https://tgftp.nws.noaa.gov/data/observations/metar/cycles/" + req.params.filename;
        noaaMirrorCtrl._mirror_url(metarUrl, 0, 15, res);
    };
    noaaMirrorCtrl.gfs = function(req, res) {
        function getGfsUrl() {
            const dateParams = noaaMirrorCtrl._getDateParams();
            let url = sprintf("https://nomads.ncep.noaa.gov/cgi-bin/filter_gfs_1p00.pl?dir=%%2Fgfs.%s&file=gfs.t%02dz.pgrb2.1p00.f0%02d", dateParams['dateCycle'], dateParams['cycle'], dateParams['forecast']);
            const levels = ["700_mb","250_mb"]; // 9,878 and 33,985 ft
            levels.forEach(function(level) {
                url += "&lev_" + level + "=1";
            });
            const vars = ["UGRD", "VGRD"];
            vars.forEach(function(v) {
                url += "&var_" + v + "=1";
            });
            return url;
        }

        // TODO: Serve old URL if the latest isn't available
        noaaMirrorCtrl._mirror_url(getGfsUrl(), 3600, 0, res);
    };
    noaaMirrorCtrl.wafs = function(req, res) {
        function getWafsUrl() {
            const dateParams = noaaMirrorCtrl._getDateParams();
            return sprintf("https://www.ftp.ncep.noaa.gov/data/nccf/com/gfs/prod/gfs.%s/WAFS_blended_%sf%02d.grib2", dateParams['dateCycle'],  dateParams['dateCycle'], dateParams['forecast']);
        }

        // TODO: Serve old URL if the latest isn't available
        noaaMirrorCtrl._mirror_url(getWafsUrl(), 3600, 0, res);
    };

    noaaMirrorCtrl._cacheCreatedTime = {};

    // We tell memory-cache to *never* expire our stuff, so that if NOAA has extended downtime,
    // we won't expose that to our users.
    // BUT! We *do* want to update from them relatively frequently. So, we use a "soft" expiration,
    // after which we'll retry NOAA servers; in the event of failure, we continue serving whatever
    // data we had before.
    noaaMirrorCtrl.isSoftInvalidated = function(url, softInvalidateMins) {
        if(softInvalidateMins && softInvalidateMins > 0 &&
                noaaMirrorCtrl._cacheCreatedTime.hasOwnProperty(url) &&
                noaaMirrorCtrl._cacheCreatedTime[url]) {
            const softInvalidateAfterTimestampMs = Date.now() + softInvalidateMins * 60 * 1000;
            return noaaMirrorCtrl._cacheCreatedTime < softInvalidateAfterTimestampMs;
        }
        return false;
    };

    /**
     * @param urlToMirror {string} The URL whose plain-text response we want to pass through to the client
     * @param hardInvalidateMins {number} Number of minutes after which we should destroy our cached copy of the data; 0 or negative to never hard invalidate
     * @param softInvalidateMins {number} Number of minutes after which we should attempt to update our cached copy of the data (and fall back to the cache if NOAA is down); 0 or negative to never attempt an update
     * @param res The response object by which we send data to the user
     * @private
     */
    noaaMirrorCtrl._mirror_url = function(urlToMirror, hardInvalidateMins, softInvalidateMins, res) {
        function send(text) {
            res.setHeader('Content-type', 'text/plain');
            res.charset = 'UTF-8';
            res.send(text);
        }
        function errorOut(fallbackText, statusCode) {
            if(fallbackText) {
                logger.debug("Error " + statusCode + "; sending fallback text for " + urlToMirror);
                res.send(fallbackText);
            } else {
                logger.error("Error " + statusCode + "; failed to send " + urlToMirror);
                res.status(statusCode).send();
            }
        }
        function proxyLiveUrl(fallbackText) {
            http.get(urlToMirror, function(proxiedResponse) {
                if(proxiedResponse.statusCode < 400) {
                    let result = "";
                    proxiedResponse.on('data', function(chunk) {
                        result += chunk;
                    });
                    proxiedResponse.on('end', function() {
                        cache.put(urlToMirror, result, hardInvalidateMins > 0 ? hardInvalidateMins * 60 * 1000 : undefined);
                        noaaMirrorCtrl._cacheCreatedTime[urlToMirror] = Date.now();
                        logger.debug("Successfully updated cached copy of " + urlToMirror);
                        send(result);
                    });

                    proxiedResponse.on('error', (e) => {
                        logger.error("Error while updating cached copy of " + urlToMirror);
                        logger.error(e);
                        if(fallbackText) {
                            logger.debug("Sending stale cached copy");
                            send(fallbackText);
                        } else {
                            errorOut(fallbackText, 500);
                        }
                    })
                } else {
                    logger.debug("Sigh... NOAA status error updating " + urlToMirror);
                    errorOut(fallbackText, proxiedResponse.statusCode);
                }
            });
        }

        try {
            const cachedResult = cache.get(urlToMirror);
            if(cachedResult) {
                if(noaaMirrorCtrl.isSoftInvalidated(urlToMirror, softInvalidateMins)) {
                    logger.debug("Attempting to update cached copy of " + urlToMirror);
                    proxyLiveUrl(cachedResult);
                } else {
                    logger.debug("Sending cached version of " + urlToMirror);
                    send(cachedResult);
                }
            } else {
                logger.debug("Getting our first copy of " + urlToMirror);
                proxyLiveUrl();
            }
        } catch(e) {
            logger.debug("Caught an error connecting to " + urlToMirror);
            errorOut(null, 404);
        }
    };

    noaaMirrorCtrl._getDateParams = function() {
        function getDateHoursAgo(hoursAgo) {
            const d = new Date();
            d.setUTCHours(d.getUTCHours() - hoursAgo);
            return d;
        }
        const fourHoursAgo = getDateHoursAgo(4); // NOAA delays 4 hours in publishing data
        const cycle = Math.floor(fourHoursAgo.getUTCHours() / 6) * 6; // NOAA cycles are multiples of 6
        const dateCycle = sprintf("%d%02d%02d%02d", fourHoursAgo.getUTCFullYear(), fourHoursAgo.getUTCMonth() + 1, fourHoursAgo.getUTCDay(), cycle);

        const now = new Date();
        const adjs = now.getUTCDay() !== fourHoursAgo.getUTCDay() ? 24 : 0;
        const forecast = Math.floor(adjs + now.getUTCHours() - cycle) / 3 * 3;

        return {
            'dateCycle': dateCycle,
            'forecast': forecast,
            'cycle': cycle
        };
    };
})(module.exports);






