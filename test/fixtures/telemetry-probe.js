const { InMemorySpanExporter, SimpleSpanProcessor } = require('@opentelemetry/sdk-trace-base');
const { initializeTelemetry, shutdownTelemetry } = require('../../src/telemetry');

const exporter = new InMemorySpanExporter();
initializeTelemetry(
  { OTEL_TRACES_EXPORTER: 'none', OTEL_METRICS_EXPORTER: 'none', OTEL_LOGS_EXPORTER: 'none' },
  { spanProcessors: [new SimpleSpanProcessor(exporter)] }
);

const http = require('node:http');
const { createApp } = require('../../src/app');
const { createMetrics } = require('../../src/metrics');
const { createLogger } = require('../../src/logger');

function listen(server) {
  return new Promise((resolve, reject) => {
    server.once('error', reject);
    server.listen(0, '127.0.0.1', () => resolve(server.address().port));
  });
}

function close(server) {
  return new Promise((resolve, reject) => server.close((error) => (error ? reject(error) : resolve())));
}

function httpGet(options) {
  return new Promise((resolve, reject) => {
    const request = http.get(options, (response) => {
      response.resume();
      response.once('end', () => resolve(response));
    });
    request.once('error', reject);
  });
}

async function main() {
  let receivedTraceparent;
  const downstream = http.createServer((request, response) => {
    receivedTraceparent = request.headers.traceparent;
    response.end('ok');
  });
  const downstreamPort = await listen(downstream);
  const logLines = [];
  const app = createApp(
    createMetrics(),
    createLogger({ log: (line) => logLines.push(JSON.parse(line)) })
  );
  app.get('/outbound/:resource', async (_request, response, next) => {
    try {
      await httpGet({ host: '127.0.0.1', port: downstreamPort, path: '/dependency' });
      response.status(204).end();
    } catch (error) {
      next(error);
    }
  });
  const appServer = http.createServer(app);
  const appPort = await listen(appServer);

  await httpGet({ host: '127.0.0.1', port: appPort, path: '/outbound/not-a-route-label?sig=not-recorded' });
  await close(appServer);
  await close(downstream);
  const spans = exporter.getFinishedSpans().map((span) => ({
    name: span.name,
    kind: span.kind,
    traceId: span.spanContext().traceId,
    spanId: span.spanContext().spanId,
    parentSpanContext: span.parentSpanContext,
    attributes: span.attributes
  }));
  await shutdownTelemetry();

  process.stdout.write(JSON.stringify({
    log: logLines.find((line) => line.event === 'http_request_completed'),
    receivedTraceparent,
    spans
  }));
}

main().catch((error) => {
  process.stderr.write(`${error.stack || error}\n`);
  process.exitCode = 1;
});
