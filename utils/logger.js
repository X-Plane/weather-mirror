const winston = require('winston');

const mkdirp = require( 'mkdirp');
mkdirp('log');

const logger = new (winston.Logger)({
    level: 'debug',
    exitOnError: false,
    transports: [
        new (winston.transports.Console)(),
        new winston.transports.File({filename: "log/weather-mirror.log", json: false, level: 'info'})
    ],
    exceptionHandlers: [
        new (winston.transports.Console)(),
        new winston.transports.File({filename: "log/exceptions.log", json: false})
    ]
});

module.exports = logger;