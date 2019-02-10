(function(controllers) {
    const noaaMirrorController = require('./noaaMirrorController');

    controllers.init = function(app) {
        noaaMirrorController.init(app);

        app.use(function(req, res) {
            res.send(404, "Not Found");
        });
    };
})(module.exports);
