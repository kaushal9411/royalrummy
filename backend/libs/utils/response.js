const { v4: uuidv4 } = require('uuid');

const sendResponse = (res, statusCode, data, pagination = null, meta = {}) => {
  const response = {
    success: true,
    data,
    meta: {
      request_id: uuidv4(),
      server_time: new Date().toISOString(),
      ...meta,
    },
  };

  if (pagination) {
    response.pagination = {
      page: pagination.page,
      limit: pagination.limit,
      total: pagination.total || 0,
      has_next: (pagination.page * pagination.limit) < (pagination.total || 0),
    };
  }

  return res.status(statusCode).json(response);
};

const sendError = (res, statusCode, code, message, details = null) => {
  const response = {
    success: false,
    error: { code, message },
    meta: {
      request_id: uuidv4(),
      server_time: new Date().toISOString(),
    },
  };

  if (details) response.error.details = details;

  return res.status(statusCode).json(response);
};

module.exports = { sendResponse, sendError };
