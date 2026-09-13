const request = require('supertest');
const createApp = require('./app');

describe('backend API', () => {
  const app = createApp();

  test('GET /api/health returns 200 ok', async () => {
    const res = await request(app).get('/api/health');
    expect(res.status).toBe(200);
    expect(res.body).toEqual({ status: 'ok' });
  });

  test('GET /api/status returns SUCCESS with a v4 guid', async () => {
    const res = await request(app).get('/api/status');
    expect(res.status).toBe(200);
    expect(res.body.status).toBe('SUCCESS');
    expect(res.body.guid).toMatch(
      /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i
    );
  });

  test('GET /api/status returns a different guid on each call', async () => {
    const res1 = await request(app).get('/api/status');
    const res2 = await request(app).get('/api/status');
    expect(res1.body.guid).not.toBe(res2.body.guid);
  });

  test('unknown route returns 404', async () => {
    const res = await request(app).get('/api/does-not-exist');
    expect(res.status).toBe(404);
  });
});
