(function(controllers) {
    const noaaMirrorController = require('./noaaMirrorController');

    controllers.init = function(app) {
        noaaMirrorController.init(app);

        app.use(function(req, res) {
            res.status(404).send();
        });
    };
})(module.exports);
