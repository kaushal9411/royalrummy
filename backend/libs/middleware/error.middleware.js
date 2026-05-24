const logger = require('../utils/logger');

/**
 * Global Express error handler — must be registered LAST in the middleware chain.
 * Catches all errors thrown with next(err) or thrown inside async handlers.
 */
const errorHandler = (err, req, res, next) => {
  // Log error details
  logger.error({
    message: err.message,
    stack: process.env.NODE_ENV !== 'production' ? err.stack : undefined,
    method: req.method,
    url: req.originalUrl,
    ip: req.ip,
    userId: req.user?.id,
  });

  // Handle specific error types
  if (err.name === 'ValidationError') {
    return res.status(400).json({
      success: false,
      error: {
        code: 'GENERAL_002',
        message: 'Validation failed',
        details: err.details || err.message,
      },
    });
  }

  if (err.name === 'UnauthorizedError' || err.status === 401) {
    return res.status(401).json({
      success: false,
      error: { code: 'AUTH_006', message: 'Unauthorized' },
    });
  }

  if (err.status === 403) {
    return res.status(403).json({
      success: false,
      error: { code: 'AUTH_FORBIDDEN', message: 'Forbidden' },
    });
  }

  if (err.status === 404) {
    return res.status(404).json({
      success: false,
      error: { code: 'GENERAL_003', message: err.message || 'Not found' },
    });
  }

  if (err.status === 409) {
    return res.status(409).json({
      success: false,
      error: { code: err.code || 'CONFLICT', message: err.message },
    });
  }

  // Database errors
  if (err.code === '23505') {
    return res.status(409).json({
      success: false,
      error: { code: 'DUPLICATE_ENTRY', message: 'Duplicate entry' },
    });
  }

  if (err.code === '23503') {
    return res.status(400).json({
      success: false,
      error: { code: 'FOREIGN_KEY_VIOLATION', message: 'Referenced resource not found' },
    });
  }

  // Default: 500 Internal Server Error
  const statusCode = err.status || err.statusCode || 500;
  return res.status(statusCode).json({
    success: false,
    error: {
      code: 'GENERAL_003',
      message: process.env.NODE_ENV === 'production'
        ? 'Internal server error'
        : err.message,
    },
  });
};

/**
 * Wrap async route handlers to catch promise rejections
 */
const asyncHandler = (fn) => (req, res, next) => {
  Promise.resolve(fn(req, res, next)).catch(next);
};

module.exports = { errorHandler, asyncHandler };
