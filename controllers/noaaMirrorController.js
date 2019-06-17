(function(noaaMirrorCtrl) {
    const logger = require('../utils/logger');
    const useHttps = true;
    const http = useHttps ? require('https') : require('http');
    const cache = require('memory-cache');
    const sprintf  = require('sprintf-js').sprintf;

    noaaMirrorCtrl.init = function(app) {
        function defineGetRoute(urlToHandle, generateMirrorUrl) {
            app.get(urlToHandle, function(req, res) {
                try {
                    // Tyler says: check at least every 15 mins, because the NOAA data can change after the start of the hour... sigh...
                    noaaMirrorCtrl._mirror_url(generateMirrorUrl(), Math.min(15, noaaMirrorCtrl._minsUntilNextHour()), res);
                } catch(err) {
                    logger.error(urlToHandle + " - uncaught exception", err);
                    res.send(500, "An unknown error occurred");
                }
            });
        }

        defineGetRoute('/metar/', noaaMirrorCtrl._getMetarUrl);
        defineGetRoute('/gfs/',   noaaMirrorCtrl._getGfsUrl);
        defineGetRoute('/wafs/',  noaaMirrorCtrl._getWafsUrl);

        noaaMirrorCtrl._selfTest();
    };

    noaaMirrorCtrl._getMetarUrl = function(overrideDate) {
        const d = overrideDate ? new Date(overrideDate.getTime()) : new Date();
        const prevHour = (23 + d.getUTCHours()) % 24; // go 1 hour into the past because the current hour at this site is always 0 bytes!
        const txtFile = sprintf("%02dZ.TXT", prevHour);
        return "https://tgftp.nws.noaa.gov/data/observations/metar/cycles/" + txtFile;
    };

    noaaMirrorCtrl._getWafsUrl = function(overrideDate) {
        const dateParams = noaaMirrorCtrl._getDateParams(overrideDate);
        if (dateParams['forecast'] < 6) {
            dateParams['forecast'] = 6; // Magic constants! What do they do? Who knows! But this matches what we previously received from the dev who integrated global winds download with X-Plane... :(
        }
        return sprintf("https://www.ftp.ncep.noaa.gov/data/nccf/com/gfs/prod/gfs.%s/%02d/WAFS_blended_%s%02df%02d.grib2", dateParams['dateCycle'], dateParams['cycle'], dateParams['dateCycle'], dateParams['cycle'], dateParams['forecast']);
    };

    noaaMirrorCtrl._getGfsUrl = function(overrideDate) {
        const dateParams = noaaMirrorCtrl._getDateParams(overrideDate);
        let url = sprintf("https://nomads.ncep.noaa.gov/cgi-bin/filter_gfs_1p00.pl?dir=%%2Fgfs.%s/%02d&file=gfs.t%02dz.pgrb2.1p00.f0%02d", dateParams['dateCycle'], dateParams['cycle'], dateParams['cycle'], dateParams['forecast']);
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

    noaaMirrorCtrl._cacheSoftInvalidateTime = {};

    // We tell memory-cache to *never* expire our stuff, so that if NOAA has extended downtime,
    // we won't expose that to our users.
    // BUT! We *do* want to update from them relatively frequently. So, we use a "soft" expiration,
    // after which we'll retry NOAA servers; in the event of failure, we continue serving whatever
    // data we had before.
    noaaMirrorCtrl.isSoftInvalidated = function(route) {
        return  noaaMirrorCtrl._cacheSoftInvalidateTime.hasOwnProperty(route) &&
                noaaMirrorCtrl._cacheSoftInvalidateTime[route] > 0 &&
                noaaMirrorCtrl._cacheSoftInvalidateTime[route] < Date.now();
    };

    /**
     * @param urlToMirror {string} The URL whose plain-text response we want to forward if we grab live data
     * @param softInvalidateMins {number} Number of minutes after creation when we should attempt to update our cached copy of the data (and fall back to the cache if NOAA is down); 0 or negative to never attempt an update
     * @param res The response object by which we send data to the user
     * @private
     */
    noaaMirrorCtrl._mirror_url = function(urlToMirror, softInvalidateMins, res) {
        function send(headersAndData) {
            res.set(headersAndData['headers']);
            res.send(headersAndData['data']);
        }
        function errorOut(fallbackHeadersAndData, statusCode, optionalError) {
            if(fallbackHeadersAndData) {
                logger.debug("Error " + statusCode + "; sending stale cache for " + urlToMirror);
                if(optionalError) { logger.error(optionalError); }
                send(fallbackHeadersAndData);
            } else {
                logger.error("Error " + statusCode + "; failed to send " + urlToMirror);
                if(optionalError) { logger.error(optionalError); }
                res.status(statusCode).send();
            }
        }
        function proxyLiveUrl(fallbackHeadersAndData) {
            function errHandler(e) {
                logger.error("Error while updating cached copy of " + urlToMirror);
                errorOut(fallbackHeadersAndData, 500, e);
            }
            http.get(urlToMirror, {encoding: null}, function(proxiedResponse) {
                if(proxiedResponse.statusCode < 400) {
                    const resultBuffers = []; // array of Buffer objects
                    proxiedResponse.on('data', function(chunk) {
                        resultBuffers.push(chunk);
                    });
                    proxiedResponse.on('end', function() {
                        const responseToCache = {'headers': proxiedResponse.headers, 'data': Buffer.concat(resultBuffers)};
                        cache.put(res.req.originalUrl, responseToCache);
                        noaaMirrorCtrl._cacheSoftInvalidateTime[res.req.originalUrl] = Date.now() + softInvalidateMins * 60 * 1000;
                        logger.debug("Successfully updated cached copy of " + urlToMirror);
                        send(responseToCache);
                    });
                    proxiedResponse.on('error', errHandler);
                } else {
                    logger.debug("Sigh... NOAA status error updating " + urlToMirror);
                    errorOut(fallbackHeadersAndData, proxiedResponse.statusCode);
                }
            }).on('error', errHandler);
        }

        try {
            const cachedResult = cache.get(res.req.originalUrl);
            if(cachedResult) {
                if(noaaMirrorCtrl.isSoftInvalidated(res.req.originalUrl)) {
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
            errorOut(null, 404, e);
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
        const dateCycle = sprintf("%d%02d%02d", fourHoursAgo.getUTCFullYear(), fourHoursAgo.getUTCMonth() + 1, fourHoursAgo.getUTCDate());

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
        function testForDate(testDate, correctGfs, correctWafs) {
            const gfs = noaaMirrorCtrl._getGfsUrl(testDate);
            if(gfs !== correctGfs) {
                console.error('GFS URL is wrong');
                console.error('Ours:    ' + gfs);
                console.error('Correct: ' + correctGfs);
                throw new Error("Incorrect URLs in self-test");
            }

            const wafs = noaaMirrorCtrl._getWafsUrl(testDate);
            if(wafs !== correctWafs) {
                console.error('WAFS URL is wrong');
                console.error('Ours:    ' + wafs);
                console.error('Correct: ' + correctWafs);
                throw new Error("Incorrect URLs in self-test");
            }
        }

        const testDate1 = new Date(1549923284000);
        const dateParams = noaaMirrorCtrl._getDateParams(testDate1);
        if(dateParams['dateCycle'] !== '20190211') { throw new Error('Expected dateCycle 20190211, got ' + dateParams['dateCycle']); }
        if(dateParams['cycle'] !== 18) { throw new Error('Expected cycle 18, got ' + dateParams['cycle']); }
        if(dateParams['forecast'] !== 3) { throw new Error('Expected forecast 6, got ' + dateParams['forecast']); }

        testForDate(testDate1,
            'https://nomads.ncep.noaa.gov/cgi-bin/filter_gfs_1p00.pl?dir=%2Fgfs.20190211/18&file=gfs.t18z.pgrb2.1p00.f003&lev_700_mb=1&lev_250_mb=1&var_UGRD=1&var_VGRD=1',
            'https://www.ftp.ncep.noaa.gov/data/nccf/com/gfs/prod/gfs.20190211/18/WAFS_blended_2019021118f06.grib2');

        testForDate(new Date(1550025476382), // 6 hours ago will cross the date boundary
            'https://nomads.ncep.noaa.gov/cgi-bin/filter_gfs_1p00.pl?dir=%2Fgfs.20190212/18&file=gfs.t18z.pgrb2.1p00.f006&lev_700_mb=1&lev_250_mb=1&var_UGRD=1&var_VGRD=1',
            'https://www.ftp.ncep.noaa.gov/data/nccf/com/gfs/prod/gfs.20190212/18/WAFS_blended_2019021218f06.grib2');
        testForDate(new Date(1549992766227),
            'https://nomads.ncep.noaa.gov/cgi-bin/filter_gfs_1p00.pl?dir=%2Fgfs.20190212/12&file=gfs.t12z.pgrb2.1p00.f003&lev_700_mb=1&lev_250_mb=1&var_UGRD=1&var_VGRD=1',
            'https://www.ftp.ncep.noaa.gov/data/nccf/com/gfs/prod/gfs.20190212/12/WAFS_blended_2019021212f06.grib2');

        if(noaaMirrorCtrl._getMetarUrl(new Date(1550019493626)) !== "https://tgftp.nws.noaa.gov/data/observations/metar/cycles/23Z.TXT") {
            throw new Error("Incorrect METAR URL in self-test");
        }
    };
})(module.exports);






