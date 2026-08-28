const express = require('express');
const client = require('@prometheus-io/client');

const METRIC_PREFIX = 'jenkins_webapp_';

function createMetrics() {
  const registry = new client.Registry();

  registry.setDefaultLabels({ service: 'jenkins-webapp' });
  client.collectDefaultMetrics({ prefix: METRIC_PREFIX, register: registry });

  const requestsTotal = new client.Counter({
    name: `${METRIC_PREFIX}http_requests_total`,
    help: 'Total HTTP requests handled by the application.',
    labelNames: ['method', 'route', 'status_code'],
    registers: [registry]
  });

  const requestDuration = new client.Histogram({
    name: `${METRIC_PREFIX}http_request_duration_seconds`,
    help: 'Application HTTP request duration in seconds.',
    labelNames: ['method', 'route', 'status_code'],
    buckets: [0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5],
    registers: [registry]
  });

  const requestsInFlight = new client.Gauge({
    name: `${METRIC_PREFIX}http_requests_in_flight`,
    help: 'Current number of application HTTP requests being handled.',
    registers: [registry]
  });

  function middleware(request, response, next) {
    requestsInFlight.inc();
    const stopTimer = requestDuration.startTimer();
    let requestCompleted = false;

    const releaseInFlight = () => {
      if (!requestCompleted) {
        requestCompleted = true;
        requestsInFlight.dec();
      }
    };

    response.once('finish', () => {
      const labels = {
        method: request.method,
        route: request.route?.path || 'unmatched',
        status_code: String(response.statusCode)
      };

      requestsTotal.inc(labels);
      stopTimer(labels);
      releaseInFlight();
    });
    response.once('close', releaseInFlight);

    next();
  }

  return { middleware, registry };
}

function createMetricsApp(metrics) {
  const app = express();
  app.disable('x-powered-by');

  app.get('/metrics', async (_request, response, next) => {
    try {
      response.set('Content-Type', metrics.registry.contentType);
      response.send(await metrics.registry.metrics());
    } catch (error) {
      next(error);
    }
  });

  return app;
}

module.exports = { createMetrics, createMetricsApp, METRIC_PREFIX };
