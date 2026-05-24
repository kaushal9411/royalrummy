const logger = require('../utils/logger');

/**
 * Request logger middleware — logs method, path, status, duration, userId
 */
const requestLogger = (req, res, next) => {
  const start = Date.now();

  res.on('finish', () => {
    const duration = Date.now() - start;
    const level = res.statusCode >= 500 ? 'error'
      : res.statusCode >= 400 ? 'warn'
      : 'info';

    logger[level]({
      type: 'http',
      method: req.method,
      url: req.originalUrl,
      status: res.statusCode,
      duration_ms: duration,
      ip: req.headers['x-forwarded-for'] || req.ip,
      user_id: req.user?.id || null,
      device_id: req.headers['x-device-id'] || null,
      app_version: req.headers['x-app-version'] || null,
    });
  });

  next();
};

module.exports = { requestLogger };
