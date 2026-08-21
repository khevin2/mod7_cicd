const request = require('supertest');

const { createApp, SERVICE_NAME } = require('../src/app');

describe('Express service', () => {
  const app = createApp();

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
});
