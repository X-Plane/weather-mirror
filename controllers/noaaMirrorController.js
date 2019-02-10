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
    };

    /**
     * Serves the METAR file from either our in-memory cache or by forwarding on the response from the NOAA server.
     */
    noaaMirrorCtrl.metar = function(req, res) {
        const metarUrl = "https://tgftp.nws.noaa.gov/data/observations/metar/cycles/" + req.params.filename;
        noaaMirrorCtrl._mirror_url(metarUrl, 0, 15, res);
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
})(module.exports);






