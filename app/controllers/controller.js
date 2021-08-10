const { response } = require("express");

let data = {
    message: "hello world"
}
// get data
exports.get = (req, res) => {
    res.status(200).send(data);
};

// Update the data
exports.update = (req, res) => {
    // Validate Request because title is required
    const key = req.params.key;
    const message = req.params.message;
    if(key && message) {
        data[key]=message;
    }
    res.status(200).send("ok");
};

exports.delete = (req, res) => {
    const key = req.params.key;
    if(key) {
        delete data[key];
    }
    res.status(200).send("ok");
}