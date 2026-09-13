const createApp = require('./app');
const config = require('../config');

const app = createApp();

const server = app.listen(config.port, config.host, () => {
  // eslint-disable-next-line no-console
  console.log(`Backend listening on ${config.host}:${config.port} (${config.nodeEnv})`);
});

function shutdown(signal) {
  // eslint-disable-next-line no-console
  console.log(`Received ${signal}, shutting down gracefully`);
  server.close((err) => {
    if (err) {
      // eslint-disable-next-line no-console
      console.error('Error during shutdown', err);
      process.exit(1);
    }
    process.exit(0);
  });

  // Force-exit if connections don't close in time (e.g. ECS SIGKILL grace period).
  setTimeout(() => process.exit(1), 10000).unref();
}

process.on('SIGTERM', () => shutdown('SIGTERM'));
process.on('SIGINT', () => shutdown('SIGINT'));

module.exports = server;
