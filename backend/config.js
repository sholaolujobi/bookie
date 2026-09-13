// Backend runtime configuration, driven entirely by environment variables
// so the same image can run unmodified in local dev, containers, and ECS.

const parseOrigins = (value) =>
  (value || '')
    .split(',')
    .map((origin) => origin.trim())
    .filter(Boolean);

const config = {
  port: parseInt(process.env.PORT, 10) || 8080,
  host: process.env.HOST || '0.0.0.0',
  nodeEnv: process.env.NODE_ENV || 'development',
  // Comma-separated list of origins allowed to call this API via CORS.
  // In production this should be the deployed frontend origin (e.g. the
  // ALB DNS name), never a wildcard.
  corsOrigins: parseOrigins(process.env.CORS_ORIGIN || 'http://localhost:3000'),
};

module.exports = config;
