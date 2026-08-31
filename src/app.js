const express = require('express');

const { createMetrics } = require('./metrics');
const { createLogger } = require('./logger');

const SERVICE_NAME = 'jenkins-webapp';

function createApp(metrics = createMetrics(), logger = createLogger(), faultInjection) {
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
  app.use(express.json());

  // This path returns an error only after the separate loopback-only control
  // listener enables its in-memory switch. It has no request-controlled knobs
  // and does not affect ordinary application routes.
  app.get('/_phase11/fault', (_request, response, next) => {
    if (!faultInjection?.isEnabled()) {
      return next();
    }

    logger.warn('controlled_fault_injection', { status_code: 500 });
    return response.status(500).json({ service: SERVICE_NAME, status: 'controlled-test-error' });
  });

  app.get('/', (_request, response) => {
    response.status(200).json({
      service: SERVICE_NAME,
      message: 'Jenkins CI/CD lab service is running'
    });
  });

  app.post('/test', (req, res) => {
    const { name, value } = req.body;
    logger.info('test_endpoint_called', { name, value });
    if (value === 'error') {
      logger.error('test_endpoint_error', { name, value });
      return res.status(500).json({
        service: SERVICE_NAME,
        message: 'Test endpoint met an unexpected error'
      });
    }
    else {
      logger.info('test_endpoint_success', { name, value });
      res.status(200).json({
        service: SERVICE_NAME,
        message: 'Test endpoint is working'
      });
    }
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
