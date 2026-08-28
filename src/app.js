const express = require('express');

const { createMetrics } = require('./metrics');
const { createLogger } = require('./logger');

const SERVICE_NAME = 'jenkins-webapp';

function createApp(metrics = createMetrics(), logger = createLogger()) {
  const app = express();

  app.disable('x-powered-by');
  app.use((request, response, next) => {
    const startedAt = process.hrtime.bigint();

    response.once('finish', () => {
      const durationMs = Number(process.hrtime.bigint() - startedAt) / 1_000_000;
      logger.info('http_request_completed', {
        method: request.method,
        route: request.route?.path || 'unmatched',
        status_code: response.statusCode,
        duration_ms: Math.round(durationMs * 1000) / 1000
      });
    });

    next();
  });
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

  app.use((error, _request, response, _next) => {
    logger.error('http_request_failed', {
      error_type: 'internal_error',
      status_code: 500
    });
    response.status(500).json({ service: SERVICE_NAME, status: 'error' });
  });

  app.metrics = metrics;
  return app;
}

module.exports = { createApp, SERVICE_NAME };
