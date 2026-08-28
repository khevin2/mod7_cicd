const express = require('express');

const { createMetrics } = require('./metrics');

const SERVICE_NAME = 'jenkins-webapp';

function createApp(metrics = createMetrics()) {
  const app = express();

  app.disable('x-powered-by');
  app.use(metrics.middleware);

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

  app.metrics = metrics;
  return app;
}

module.exports = { createApp, SERVICE_NAME };
