const request = require('supertest');

const { createApp, SERVICE_NAME } = require('../src/app');
const { createMetricsApp } = require('../src/metrics');
const { createLogger } = require('../src/logger');
const { createFaultInjection } = require('../src/fault-injection');
const { createFaultControlApp, readConfig } = require('../src/server');

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
        status_code: 404
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
      expect(response.headers['content-type']).toContain('text/plain');
      expect(response.text).toContain('# HELP jenkins_webapp_http_requests_total');
    });
  });

  describe('controlled Phase 11 fault injection', () => {
    test('requires an explicit true environment value', () => {
      expect(readConfig({}).faultInjectionEnabled).toBe(false);
      expect(readConfig({ FAULT_INJECTION_ENABLED: 'true' }).faultInjectionEnabled).toBe(true);
      expect(() => readConfig({ FAULT_INJECTION_ENABLED: 'yes' })).toThrow(
        'FAULT_INJECTION_ENABLED must be either true or false'
      );
    });

    test('is disabled by default and can only be enabled through its separate controller', async () => {
      const faultInjection = createFaultInjection();
      const faultApp = createApp(undefined, undefined, faultInjection);
      const controlApp = createFaultControlApp(faultInjection);

      expect((await request(faultApp).get('/_phase11/fault')).status).toBe(404);
      expect((await request(controlApp).get('/_phase11/status')).body).toEqual({ enabled: false });
      expect((await request(controlApp).post('/_phase11/enable')).status).toBe(204);
      const faultResponse = await request(faultApp).get('/_phase11/fault');
      expect(faultResponse.status).toBe(500);
      expect(faultResponse.body).toEqual({ service: SERVICE_NAME, status: 'controlled-test-error' });
      expect((await request(controlApp).post('/_phase11/disable')).status).toBe(204);
      expect((await request(faultApp).get('/_phase11/fault')).status).toBe(404);
    });
  });
});
