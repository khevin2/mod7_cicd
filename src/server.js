const { createApp } = require('./app');
const { createMetricsApp } = require('./metrics');

const DEFAULT_PORT = 3000;
const DEFAULT_HOST = '0.0.0.0';
const DEFAULT_METRICS_PORT = 9464;
const DEFAULT_METRICS_HOST = '0.0.0.0';
const DEFAULT_SHUTDOWN_TIMEOUT_MS = 10_000;

function parseInteger(name, value, defaultValue, maximum) {
  if (value === undefined || value === '') {
    return defaultValue;
  }

  const parsedValue = Number(value);
  if (!Number.isInteger(parsedValue) || parsedValue <= 0 || parsedValue > maximum) {
    throw new Error(`${name} must be an integer between 1 and ${maximum}`);
  }

  return parsedValue;
}

function readConfig(environment = process.env) {
  return {
    host: environment.HOST || DEFAULT_HOST,
    port: parseInteger('PORT', environment.PORT, DEFAULT_PORT, 65_535),
    metricsHost: environment.METRICS_HOST || DEFAULT_METRICS_HOST,
    metricsPort: parseInteger(
      'METRICS_PORT',
      environment.METRICS_PORT,
      DEFAULT_METRICS_PORT,
      65_535
    ),
    shutdownTimeoutMs: parseInteger(
      'SHUTDOWN_TIMEOUT_MS',
      environment.SHUTDOWN_TIMEOUT_MS,
      DEFAULT_SHUTDOWN_TIMEOUT_MS,
      300_000
    )
  };
}

function registerShutdownHandlers(servers, shutdownTimeoutMs) {
  const serverList = Array.isArray(servers) ? servers : [servers];
  let shutdownStarted = false;

  const shutdown = (signal) => {
    if (shutdownStarted) {
      return;
    }

    shutdownStarted = true;
    console.log(`Received ${signal}; closing HTTP servers`);

    const forcedShutdown = setTimeout(() => {
      console.error('Graceful shutdown timed out');
      process.exit(1);
    }, shutdownTimeoutMs);
    forcedShutdown.unref();

    Promise.all(
      serverList.map(
        (server) =>
          new Promise((resolve, reject) => {
            server.close((error) => (error ? reject(error) : resolve()));
          })
      )
    )
      .then(() => {
        clearTimeout(forcedShutdown);
        console.log('HTTP servers closed');
        process.exit(0);
      })
      .catch((error) => {
        clearTimeout(forcedShutdown);
        console.error('Failed to close HTTP servers', error);
        process.exit(1);
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

  const app = createApp();
  const server = app.listen(config.port, config.host, () => {
    console.log(`Server listening on http://${config.host}:${config.port}`);
  });
  const metricsServer = createMetricsApp(app.metrics).listen(
    config.metricsPort,
    config.metricsHost,
    () => {
      console.log(
        `Metrics listening on http://${config.metricsHost}:${config.metricsPort}/metrics`
      );
    }
  );

  registerShutdownHandlers([server, metricsServer], config.shutdownTimeoutMs);
  server.metricsServer = metricsServer;
  return server;
}

if (require.main === module) {
  startServer();
}

module.exports = { readConfig, registerShutdownHandlers, startServer };
