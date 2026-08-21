const { createApp } = require('./app');

const DEFAULT_PORT = 3000;
const DEFAULT_HOST = '0.0.0.0';
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
    shutdownTimeoutMs: parseInteger(
      'SHUTDOWN_TIMEOUT_MS',
      environment.SHUTDOWN_TIMEOUT_MS,
      DEFAULT_SHUTDOWN_TIMEOUT_MS,
      300_000
    )
  };
}

function registerShutdownHandlers(server, shutdownTimeoutMs) {
  let shutdownStarted = false;

  const shutdown = (signal) => {
    if (shutdownStarted) {
      return;
    }

    shutdownStarted = true;
    console.log(`Received ${signal}; closing HTTP server`);

    const forcedShutdown = setTimeout(() => {
      console.error('Graceful shutdown timed out');
      process.exit(1);
    }, shutdownTimeoutMs);
    forcedShutdown.unref();

    server.close((error) => {
      clearTimeout(forcedShutdown);

      if (error) {
        console.error('Failed to close HTTP server', error);
        process.exit(1);
      }

      console.log('HTTP server closed');
      process.exit(0);
    });
  };

  process.once('SIGTERM', () => shutdown('SIGTERM'));
  process.once('SIGINT', () => shutdown('SIGINT'));
}

function startServer(environment = process.env) {
  const config = readConfig(environment);
  const app = createApp();
  const server = app.listen(config.port, config.host, () => {
    console.log(`Server listening on http://${config.host}:${config.port}`);
  });

  registerShutdownHandlers(server, config.shutdownTimeoutMs);
  return server;
}

if (require.main === module) {
  startServer();
}

module.exports = { readConfig, registerShutdownHandlers, startServer };
