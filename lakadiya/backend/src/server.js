require('dotenv').config();
const http = require('http');
const app = require('./app');
const { initSocket } = require('./socket/socket.manager');
const { pool } = require('./config/database');
const logger = require('./config/logger');

const PORT = process.env.PORT || 3001;

const server = http.createServer(app);
initSocket(server);

const start = async () => {
  try {
    await pool.query('SELECT 1');
    logger.info('Database connected');

    server.listen(PORT, () => {
      logger.info(`Server running on port ${PORT}`);
    });
  } catch (err) {
    logger.error('Failed to start server', err);
    process.exit(1);
  }
};

start();

process.on('SIGTERM', async () => {
  logger.info('SIGTERM received, shutting down');
  server.close();
  await pool.end();
  process.exit(0);
});
