const logger = require('../config/logger');

const errorHandler = (err, req, res, next) => {
  logger.error(err.message, { stack: err.stack, path: req.path });

  if (err.type === 'validation') {
    return res.status(400).json({ message: err.message, errors: err.errors });
  }

  const status = err.status || 500;
  res.status(status).json({
    message: status === 500 ? 'Internal server error' : err.message,
  });
};

const notFound = (req, res) => {
  res.status(404).json({ message: `Route ${req.path} not found` });
};

module.exports = { errorHandler, notFound };
