/**
* Copyright 2014 IBM
*
*   Licensed under the Apache License, Version 2.0 (the "License");
*   you may not use this file except in compliance with the License.
*   You may obtain a copy of the License at
*
*     http://www.apache.org/licenses/LICENSE-2.0
*
*   Unless required by applicable law or agreed to in writing, software
*   distributed under the License is distributed on an "AS IS" BASIS,
*   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
*   See the License for the specific language governing permissions and
**/

const express = require('express');
const bodyParser = require('body-parser');
const PORT = 8080;

const app = express();
const swaggerUi = require('swagger-ui-express'),
swaggerDocument = require('./swagger.json');
// parse requests of content-type - application/x-www-form-urlencoded
app.use(bodyParser.urlencoded({ extended: true }))

// parse requests of content-type - application/json
app.use(bodyParser.json())


require('./app/routes/routes.js')(app);
app.get('/',  (req, res) => {
  res.send('Welcome to IBM Cloud DevOps with Tekton (built with the COCOA pipeline). Let\'s go use the Continuous Delivery Service.!!');
});

app.use(
  '/api-docs',
  swaggerUi.serve, 
  swaggerUi.setup(swaggerDocument)
);

app.listen(PORT);
// test
console.log('Application running on port: ' + PORT);