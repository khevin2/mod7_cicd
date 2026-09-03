const request = require('supertest');
const { execFileSync } = require('node:child_process');
const path = require('node:path');

const { createApp, SERVICE_NAME, TEST_LATENCY_MS } = require('../src/app');
const { createMetrics, createMetricsApp } = require('../src/metrics');
const { createLogger } = require('../src/logger');
const { readTelemetryConfig } = require('../src/telemetry');
const { getLogTraceFields, isValidTraceContext } = require('../src/trace-context');

describe('Express service', () => {
  const app = createApp();
  const metrics = app.metrics;

  describe('GET /', () => {
    test('returns HTTP 200 with JSON content', async () => {
      const response = await request(app).get('/');

      expect(response.status).toBe(200);
      expect(response.type).toBe('application/json');
    });

    test('returns the user-facing response shape', async () => {
      const response = await request(app).get('/');

      expect(response.body).toEqual({
        service: SERVICE_NAME,
        message: 'Jenkins CI/CD lab service is running'
      });
    });
  });

  describe('GET /health', () => {
    test('returns HTTP 200 with JSON content', async () => {
      const response = await request(app).get('/health');

      expect(response.status).toBe(200);
      expect(response.type).toBe('application/json');
    });

    test('returns the deployment health response shape', async () => {
      const response = await request(app).get('/health');

      expect(response.body).toEqual({
        service: SERVICE_NAME,
        status: 'ok'
      });
    });
  });

  describe('structured application logs', () => {
    test('write only the approved request fields without sensitive request data', async () => {
      const lines = [];
      const logger = createLogger({ log: (line) => lines.push(JSON.parse(line)) }, () => '2026-08-28T00:00:00.000Z');
      const loggedApp = createApp(undefined, logger);

      await request(loggedApp)
        .get('/not-found?token=not-for-logs')
        .set('Authorization', 'Bearer not-for-logs')
        .set('Cookie', 'session=not-for-logs');

      expect(lines).toHaveLength(1);
      expect(lines[0]).toMatchObject({
        timestamp: '2026-08-28T00:00:00.000Z',
        level: 'info',
        event: 'http_request_completed',
        method: 'GET',
        route: 'unmatched',
        status_code: 404,
        trace_id: null,
        span_id: null
      });
      expect(lines[0]).not.toHaveProperty('headers');
      expect(lines[0]).not.toHaveProperty('body');
      expect(JSON.stringify(lines[0])).not.toContain('not-for-logs');
    });
  });

  describe('Prometheus metrics', () => {
    test('records requests with bounded route and status labels', async () => {
      await request(app).get('/');
      await request(app).get('/does-not-exist');

      const output = await metrics.registry.metrics();

      expect(output).toContain(
        'jenkins_webapp_http_requests_total{method="GET",route="/",status_code="200",service="jenkins-webapp"}'
      );
      expect(output).toContain(
        'jenkins_webapp_http_requests_total{method="GET",route="unmatched",status_code="404",service="jenkins-webapp"}'
      );
      expect(output).toContain('jenkins_webapp_http_request_duration_seconds_bucket');
    });

    test('serves Prometheus text only from the dedicated metrics app', async () => {
      const response = await request(createMetricsApp(metrics)).get('/metrics');

      expect(response.status).toBe(200);
      expect(response.headers['content-type']).toContain('application/openmetrics-text');
      expect(response.text).toContain('# HELP jenkins_webapp_http_requests');
      expect(response.text).toContain('# EOF');
    });

    test('attaches sampled trace context as an OpenMetrics duration exemplar without new metric labels', async () => {
      const traceContext = {
        traceId: '0123456789abcdef0123456789abcdef',
        spanId: '0123456789abcdef',
      };
      const exemplarMetrics = createMetrics(() => traceContext);
      const lines = [];
      const logger = createLogger(
        { log: (line) => lines.push(JSON.parse(line)) },
        () => '2026-08-28T00:00:00.000Z',
        () => traceContext
      );
      const tracedApp = createApp(exemplarMetrics, logger, () => traceContext);

      await request(tracedApp).get('/');
      const output = await exemplarMetrics.registry.metrics();

      expect(lines[0]).toMatchObject({
        trace_id: traceContext.traceId,
        span_id: traceContext.spanId,
      });
      expect(output).toMatch(
        /# \{traceId="0123456789abcdef0123456789abcdef",spanId="0123456789abcdef"\}/
      );
      expect(output).not.toContain('traceId="0123456789abcdef0123456789abcdef",service=');
    });
  });

  describe('trace context safety', () => {
    test('emits IDs only for sampled, non-zero lowercase W3C contexts', () => {
      expect(isValidTraceContext({
        traceId: '0123456789abcdef0123456789abcdef', spanId: '0123456789abcdef', traceFlags: 1
      })).toBe(true);
      expect(isValidTraceContext({
        traceId: '00000000000000000000000000000000', spanId: '0123456789abcdef', traceFlags: 1
      })).toBe(false);
      expect(getLogTraceFields()).toEqual({ trace_id: null, span_id: null });
    });
  });

  describe('OpenTelemetry instrumentation', () => {
    test('creates route-stable server and child client spans with W3C propagation and correlated JSON logs', () => {
      const output = execFileSync(process.execPath, [path.join(__dirname, 'fixtures/telemetry-probe.js')], {
        encoding: 'utf8'
      });
      const probe = JSON.parse(output);
      const serverSpan = probe.spans.find((span) => span.kind === 1 && span.name === 'GET /outbound/:resource');
      const clientSpan = probe.spans.find((span) => span.kind === 2 && span.attributes['server.address'] === '127.0.0.1');

      expect(serverSpan).toBeDefined();
      expect(clientSpan).toBeDefined();
      expect(clientSpan.traceId).toBe(serverSpan.traceId);
      expect(probe.receivedTraceparent).toMatch(/^00-[0-9a-f]{32}-[0-9a-f]{16}-01$/);
      expect(probe.log).toMatchObject({ trace_id: serverSpan.traceId, span_id: serverSpan.spanId });
      expect(JSON.stringify(probe)).not.toContain('sig=not-recorded');
    });
  });

  describe('POST /test test capabilities', () => {
    test('retains the deliberate error response', async () => {
      const response = await request(createApp()).post('/test').send({ value: 'error' });

      expect(response.status).toBe(500);
      expect(response.body).toEqual({
        service: SERVICE_NAME,
        message: 'Test endpoint met an unexpected error'
      });
    });

    test('uses a fixed latency response without request-controlled timing', async () => {
      const delays = [];
      const testApp = createApp(undefined, undefined, undefined, async (milliseconds) => {
        delays.push(milliseconds);
      });

      const response = await request(testApp).post('/test').send({ name: 'ignored', value: 'latency', delay: 1 });
      expect(response.body).toEqual({
        service: SERVICE_NAME, message: 'Test endpoint latency response'
      });
      expect(delays).toEqual([TEST_LATENCY_MS]);
    });
  });

  describe('Phase 1 telemetry contract', () => {
    test('is network-silent by default for local tests and development', () => {
      expect(readTelemetryConfig({})).toMatchObject({
        tracesExporter: 'none',
        samplingRatio: 1,
        serviceName: 'jenkins-webapp',
        serviceVersion: '1.0.0',
        deploymentEnvironment: 'lab'
      });
    });

    test('requires an explicit private OTLP HTTP/protobuf traces endpoint in production', () => {
      const environment = {
        NODE_ENV: 'production',
        OTEL_TRACES_EXPORTER: 'otlp',
        OTEL_EXPORTER_OTLP_PROTOCOL: 'http/protobuf',
        OTEL_EXPORTER_OTLP_TRACES_ENDPOINT: 'http://10.42.0.15:4318/v1/traces',
        OTEL_SERVICE_NAME: 'jenkins-webapp',
        OTEL_TRACES_SAMPLER: 'parentbased_traceidratio',
        OTEL_TRACES_SAMPLER_ARG: '1',
        SERVICE_VERSION: 'sha-abcdef0'
      };
      expect(readTelemetryConfig(environment)).toMatchObject({
        endpoint: 'http://10.42.0.15:4318/v1/traces',
        samplingRatio: 1,
        serviceVersion: 'sha-abcdef0',
        tracesExporter: 'otlp'
      });
      expect(() => readTelemetryConfig({ NODE_ENV: 'production' })).toThrow('Production requires');
      expect(() => readTelemetryConfig({
        OTEL_TRACES_EXPORTER: 'otlp',
        OTEL_EXPORTER_OTLP_TRACES_ENDPOINT: 'https://collector.example.com:4318/v1/traces'
      })).toThrow('credential-free private HTTP URL');
    });

    test('rejects exporter credentials, unsupported resource overrides, and invalid sampling', () => {
      expect(() => readTelemetryConfig({
        OTEL_TRACES_EXPORTER: 'otlp',
        OTEL_EXPORTER_OTLP_TRACES_ENDPOINT: 'http://user:password@10.42.0.15:4318/v1/traces'
      })).toThrow('credential-free private HTTP URL');
      expect(() => readTelemetryConfig({ OTEL_RESOURCE_ATTRIBUTES: 'cloud.account.id=not-allowed' })).toThrow('invalid cloud.account.id');
      expect(() => readTelemetryConfig({ OTEL_TRACES_SAMPLER_ARG: '1.01' })).toThrow('between 0 and 1');
    });
  });
});
