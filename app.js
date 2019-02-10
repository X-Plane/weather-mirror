/**
 * Module dependencies.
 */

const logger = require("./utils/logger");
const dotenv = require('dotenv');

// Read the config vars in our .env file; these go into process.env
// Tyler says: this needs to come before loading our controllers, because the controllers may
//             initialize themselves differently in test mode.
dotenv.load();
logger.info("Launching in", process.env.NODE_ENV, "mode.");

const express = require('express');
const http = require('http');
const controllers = require("./controllers");
const compression = require('compression');

process.on('uncaughtException', function(err) {
    logger.error(err);
    if(err && 'stack' in err) {
        logger.error(err.stack);
    }
    logger.info("Node NOT Exiting...");  //  <- Not a good thing...  We need to find the cause of the exception and stop it from getting this far.
});

const app = express();
app.set('port', parseInt(process.env.PORT) || 49100);
app.use(compression());
app.use(function errorHandler(err, req, res, next) {
    let errorCode = parseInt(err.status);
    if(errorCode <= 200 || errorCode > 599) {
        errorCode = 500;
    }
    logger.error({msg: "Top-level error in errorHandler(), app.js", error: err});
    res.render(errorCode, err.message || "Unhandled exception");
});
// Map the routes
controllers.init(app);

// Initialize memwatch, if applicable
try {
    const memwatch = require('memwatch-next');
    const heapdump = require('heapdump');
    memwatch.on('leak', function(info) {
        logger.error({
            label: 'Memory leak detected',
            timestamp: Date.now(),
            info: info
        });
        const file = '/tmp/gateway-' + process.pid + '-' + Date.now() + '.heapsnapshot';
        heapdump.writeSnapshot(file, function(err) {
            if(err) console.error(err);
            else console.error('Wrote snapshot: ' + file);
        });
    });
} catch(e) {
    console.log("Running without memwatch");
}

http.createServer(app).listen(app.get('port'), function() {
    logger.info('Express server listening on port ' + app.get('port'));
});

exports.app = app;

