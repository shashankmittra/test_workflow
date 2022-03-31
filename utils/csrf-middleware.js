const csrf = require('csurf');

const csrfProtection = csrf({ 
    cookie: {
        httpOnly: true,
        sameSite: 'strict'
    },
 });

module.exports = csrfProtection;
