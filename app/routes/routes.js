module.exports = (app) => {
    const data = require('../controllers/controller.js');
    //get all data
    app.get('/data', data.get);
    //update data
    app.put('/data/:key/:message', data.update);
    //delete data
    app.delete('/data/:key', data.delete);
}
