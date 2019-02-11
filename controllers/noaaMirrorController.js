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

        noaaMirrorCtrl._selfTest();
    };

    /**
     * Serves the METAR file from either our in-memory cache or by forwarding on the response from the NOAA server.
     */
    noaaMirrorCtrl.metar = function(req, res) {
        const metarUrl = "https://tgftp.nws.noaa.gov/data/observations/metar/cycles/" + req.params.filename;
        noaaMirrorCtrl._mirror_url(metarUrl, 15, res);
    };
    noaaMirrorCtrl.gfs = function(req, res) {
        noaaMirrorCtrl._mirror_url(noaaMirrorCtrl._getGfsUrl(), noaaMirrorCtrl._minsUntilNextHour(), res);
    };
    noaaMirrorCtrl.wafs = function(req, res) {
        noaaMirrorCtrl._mirror_url(noaaMirrorCtrl._getWafsUrl(), noaaMirrorCtrl._minsUntilNextHour(), res);
    };


    noaaMirrorCtrl._getWafsUrl = function(overrideDate) {
        const dateParams = noaaMirrorCtrl._getDateParams(overrideDate);
        if (dateParams['forecast'] < 6) {
            dateParams['forecast'] = 6; // Magic constants! What do they do? Who knows! But this matches what we previously received from the dev who integrated global winds download with X-Plane... :(
        }
        return sprintf("https://www.ftp.ncep.noaa.gov/data/nccf/com/gfs/prod/gfs.%s/WAFS_blended_%sf%02d.grib2", dateParams['dateCycle'],  dateParams['dateCycle'], dateParams['forecast']);
    };

    noaaMirrorCtrl._getGfsUrl = function(overrideDate) {
        const dateParams = noaaMirrorCtrl._getDateParams(overrideDate);
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
    };

    noaaMirrorCtrl._cacheCreatedTime = {};

    // We tell memory-cache to *never* expire our stuff, so that if NOAA has extended downtime,
    // we won't expose that to our users.
    // BUT! We *do* want to update from them relatively frequently. So, we use a "soft" expiration,
    // after which we'll retry NOAA servers; in the event of failure, we continue serving whatever
    // data we had before.
    noaaMirrorCtrl.isSoftInvalidated = function(route, softInvalidateMins) {
        if(softInvalidateMins && softInvalidateMins > 0 &&
                noaaMirrorCtrl._cacheCreatedTime.hasOwnProperty(route) &&
                noaaMirrorCtrl._cacheCreatedTime[route]) {
            const softInvalidateAfterTimestampMs = Date.now() + softInvalidateMins * 60 * 1000;
            return noaaMirrorCtrl._cacheCreatedTime < softInvalidateAfterTimestampMs;
        }
        return false;
    };

    /**
     * @param urlToMirror {string} The URL whose plain-text response we want to forward if we grab live data
     * @param softInvalidateMins {number} Number of minutes after which we should attempt to update our cached copy of the data (and fall back to the cache if NOAA is down); 0 or negative to never attempt an update
     * @param res The response object by which we send data to the user
     * @private
     */
    noaaMirrorCtrl._mirror_url = function(urlToMirror, softInvalidateMins, res) {
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
                        cache.put(res.req.originalUrl, result);
                        noaaMirrorCtrl._cacheCreatedTime[res.req.originalUrl] = Date.now();
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
            const cachedResult = cache.get(res.req.originalUrl);
            if(cachedResult) {
                if(noaaMirrorCtrl.isSoftInvalidated(res.req.originalUrl, softInvalidateMins)) {
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

    noaaMirrorCtrl._getDateParams = function(overrideDate) {
        function getDateHoursAgo(hoursAgo, overrideDate) {
            const d = overrideDate ? new Date(overrideDate.getTime()) : new Date();
            d.setUTCHours(d.getUTCHours() - hoursAgo);
            return d;
        }
        const fourHoursAgo = getDateHoursAgo(4, overrideDate); // NOAA delays 4 hours in publishing data
        const cycle = Math.floor(fourHoursAgo.getUTCHours() / 6) * 6; // NOAA cycles are multiples of 6
        const dateCycle = sprintf("%d%02d%02d%02d", fourHoursAgo.getUTCFullYear(), fourHoursAgo.getUTCMonth() + 1, fourHoursAgo.getUTCDate(), cycle);

        const now = overrideDate ? new Date(overrideDate.getTime()) : new Date();
        const adjs = now.getUTCDate() === fourHoursAgo.getUTCDate() ? 0 : 24;
        const forecast = Math.floor((adjs + now.getUTCHours() - cycle) / 3) * 3;

        return {
            'dateCycle': dateCycle,
            'forecast': forecast,
            'cycle': cycle
        };
    };

    noaaMirrorCtrl._minsUntilNextHour = function() {
        const now = new Date();
        return 60 - now.getUTCMinutes();
    };

    noaaMirrorCtrl._selfTest = function() {
        const testDate = new Date(1549923284000);
        const dateParams = noaaMirrorCtrl._getDateParams(testDate);
        if(dateParams['dateCycle'] !== '2019021118') { throw new Error('Expected dateCycle 2019021118, got ' + dateParams['dateCycle']); }
        if(dateParams['cycle'] !== 18) { throw new Error('Expected cycle 18, got ' + dateParams['cycle']); }
        if(dateParams['forecast'] !== 3) { throw new Error('Expected forecast 6, got ' + dateParams['forecast']); }

        const correctGfs = 'https://nomads.ncep.noaa.gov/cgi-bin/filter_gfs_1p00.pl?dir=%2Fgfs.2019021118&file=gfs.t18z.pgrb2.1p00.f003&lev_700_mb=1&lev_250_mb=1&var_UGRD=1&var_VGRD=1';
        const gfs = noaaMirrorCtrl._getGfsUrl(testDate);
        if(gfs !== correctGfs) {
            console.error('GFS URL is wrong');
            console.error('Ours:    ' + gfs);
            console.error('Correct: ' + correctGfs);
            throw new Error("Incorrect URLs in self-test");
        }

        const correctWafs = 'https://www.ftp.ncep.noaa.gov/data/nccf/com/gfs/prod/gfs.2019021118/WAFS_blended_2019021118f06.grib2';
        const wafs = noaaMirrorCtrl._getWafsUrl(testDate);
        if(wafs !== correctWafs) {
            console.error('WAFS URL is wrong');
            console.error('Ours:    ' + wafs);
            console.error('Correct: ' + correctWafs);
            throw new Error("Incorrect URLs in self-test");
        }
    };
})(module.exports);






