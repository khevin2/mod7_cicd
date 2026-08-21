const express = require('express');

const SERVICE_NAME = 'jenkins-webapp';

function createApp() {
  const app = express();

  app.disable('x-powered-by');

  app.get('/', (_request, response) => {
    response.status(200).json({
      service: SERVICE_NAME,
      message: 'Jenkins CI/CD lab service is running'
    });
  });

  app.get('/health', (_request, response) => {
    response.status(200).json({
      service: SERVICE_NAME,
      status: 'ok'
    });
  });

  return app;
}

module.exports = { createApp, SERVICE_NAME };
