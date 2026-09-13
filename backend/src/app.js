const express = require('express');
const cors = require('cors');
const { v4: uuidv4 } = require('uuid');
const config = require('../config');

function createApp() {
  const app = express();

  app.disable('x-powered-by');

  const corsOptions = {
    origin(origin, callback) {
      // Allow same-origin / non-browser requests (no Origin header, e.g.
      // container health checks) and any explicitly allow-listed origin.
      if (!origin || config.corsOrigins.includes(origin)) {
        callback(null, true);
      } else {
        callback(new Error('Not allowed by CORS'));
      }
    },
    methods: ['GET', 'OPTIONS'],
  };
  app.use(cors(corsOptions));

  // Liveness/readiness probe used by the container health check, the ECS
  // task definition health check, and the ALB target group health check.
  app.get('/api/health', (req, res) => {
    res.status(200).json({ status: 'ok' });
  });

  // Primary application endpoint: returns a fresh GUID so the frontend can
  // prove it successfully reached the backend.
  app.get('/api/status', (req, res) => {
    res.status(200).json({
      status: 'SUCCESS',
      guid: uuidv4(),
      timestamp: new Date().toISOString(),
    });
  });

  app.use((req, res) => {
    res.status(404).json({ error: 'Not found' });
  });

  // eslint-disable-next-line no-unused-vars
  app.use((err, req, res, next) => {
    if (err && err.message === 'Not allowed by CORS') {
      return res.status(403).json({ error: 'Origin not allowed' });
    }
    res.status(500).json({ error: 'Internal server error' });
  });

  return app;
}

module.exports = createApp;
