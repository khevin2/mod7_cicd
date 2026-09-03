const { initializeTelemetry, shutdownTelemetry } = require('./telemetry');

// This must run before loading Express or Node's HTTP module through app.js.
initializeTelemetry();

const { createApp } = require('./app');
const { createMetricsApp } = require('./metrics');
const { createFaultInjection } = require('./fault-injection');

const DEFAULT_PORT = 3000;
const DEFAULT_HOST = '0.0.0.0';
const DEFAULT_METRICS_PORT = 9464;
const DEFAULT_METRICS_HOST = '0.0.0.0';
const DEFAULT_SHUTDOWN_TIMEOUT_MS = 10_000;
const DEFAULT_FAULT_CONTROL_PORT = 9465;

function parseInteger(name, value, defaultValue, maximum) {
  if (value === undefined || value === '') return defaultValue;
  const parsedValue = Number(value);
  if (!Number.isInteger(parsedValue) || parsedValue <= 0 || parsedValue > maximum) {
    throw new Error(`${name} must be an integer between 1 and ${maximum}`);
  }
  return parsedValue;
}

function parseBoolean(name, value, defaultValue = false) {
  if (value === undefined || value === '') return defaultValue;
  if (value === 'true') return true;
  if (value === 'false') return false;
  throw new Error(`${name} must be either true or false`);
}

function readConfig(environment = process.env) {
  return {
    host: environment.HOST || DEFAULT_HOST,
    port: parseInteger('PORT', environment.PORT, DEFAULT_PORT, 65_535),
    metricsHost: environment.METRICS_HOST || DEFAULT_METRICS_HOST,
    metricsPort: parseInteger('METRICS_PORT', environment.METRICS_PORT, DEFAULT_METRICS_PORT, 65_535),
    faultInjectionEnabled: parseBoolean('FAULT_INJECTION_ENABLED', environment.FAULT_INJECTION_ENABLED),
    faultControlPort: parseInteger('FAULT_CONTROL_PORT', environment.FAULT_CONTROL_PORT, DEFAULT_FAULT_CONTROL_PORT, 65_535),
    shutdownTimeoutMs: parseInteger('SHUTDOWN_TIMEOUT_MS', environment.SHUTDOWN_TIMEOUT_MS, DEFAULT_SHUTDOWN_TIMEOUT_MS, 300_000)
  };
}

function createFaultControlApp(faultInjection) {
  const express = require('express');
  const app = express();
  app.disable('x-powered-by');
  app.get('/_phase11/status', (_request, response) => response.json({ enabled: faultInjection.isEnabled() }));
  app.post('/_phase11/enable', (_request, response) => {
    faultInjection.enable();
    response.status(204).end();
  });
  app.post('/_phase11/disable', (_request, response) => {
    faultInjection.disable();
    response.status(204).end();
  });
  return app;
}

function registerShutdownHandlers(servers, shutdownTimeoutMs, shutdownTelemetryFn = shutdownTelemetry, exit = process.exit) {
  const serverList = Array.isArray(servers) ? servers : [servers];
  let shutdownStarted = false;
  const shutdown = (signal) => {
    if (shutdownStarted) return;
    shutdownStarted = true;
    console.log(`Received ${signal}; closing HTTP servers`);
    const forcedShutdown = setTimeout(() => {
      console.error('Graceful shutdown timed out');
      exit(1);
    }, shutdownTimeoutMs);
    forcedShutdown.unref();
    Promise.all(serverList.map((server) => new Promise((resolve, reject) => {
      server.close((error) => (error ? reject(error) : resolve()));
    })))
      // Close listeners first so completed request spans are eligible for the
      // bounded SDK flush instead of racing it during process termination.
      .then(() => shutdownTelemetryFn())
      .then(() => {
        clearTimeout(forcedShutdown);
        console.log('HTTP servers closed');
        exit(0);
      })
      .catch((error) => {
        clearTimeout(forcedShutdown);
        console.error('Failed to close HTTP servers', error);
        exit(1);
      });
  };
  process.once('SIGTERM', () => shutdown('SIGTERM'));
  process.once('SIGINT', () => shutdown('SIGINT'));
}

function startServer(environment = process.env) {
  const config = readConfig(environment);
  if (config.host === config.metricsHost && config.port === config.metricsPort) {
    throw new Error('PORT and METRICS_PORT must differ when their hosts are the same');
  }
  const faultInjection = createFaultInjection();
  const app = createApp(undefined, undefined, faultInjection);
  const server = app.listen(config.port, config.host, () => {
    console.log(`Server listening on http://${config.host}:${config.port}`);
  });
  const metricsServer = createMetricsApp(app.metrics).listen(config.metricsPort, config.metricsHost, () => {
    console.log(`Metrics listening on http://${config.metricsHost}:${config.metricsPort}/metrics`);
  });
  const servers = [server, metricsServer];
  if (config.faultInjectionEnabled) {
    const faultControlServer = createFaultControlApp(faultInjection).listen(
      config.faultControlPort,
      '127.0.0.1',
      () => console.log(`Phase 11 fault control listening on loopback port ${config.faultControlPort}`)
    );
    servers.push(faultControlServer);
    server.faultControlServer = faultControlServer;
  }
  registerShutdownHandlers(servers, config.shutdownTimeoutMs);
  server.metricsServer = metricsServer;
  return server;
}

if (require.main === module) startServer();

module.exports = { createFaultControlApp, readConfig, registerShutdownHandlers, startServer };
