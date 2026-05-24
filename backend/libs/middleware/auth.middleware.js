const jwt = require('jsonwebtoken');
const { sendError } = require('../utils/response');

const authenticateJWT = (req, res, next) => {
  const authHeader = req.headers.authorization;

  if (!authHeader || !authHeader.startsWith('Bearer ')) {
    return sendError(res, 401, 'AUTH_005', 'Authentication token required');
  }

  const token = authHeader.replace('Bearer ', '');

  try {
    const payload = jwt.verify(token, process.env.JWT_SECRET);
    req.user = {
      id: payload.sub,
      username: payload.username,
      role: payload.role,
      device_id: payload.device_id,
    };
    next();
  } catch (err) {
    if (err.name === 'TokenExpiredError') {
      return sendError(res, 401, 'AUTH_005', 'Token expired');
    }
    return sendError(res, 401, 'AUTH_006', 'Invalid token');
  }
};

const requireAdmin = (req, res, next) => {
  if (!req.user || !['admin', 'super_admin'].includes(req.user.role)) {
    return sendError(res, 403, 'AUTH_FORBIDDEN', 'Admin access required');
  }
  next();
};

const requirePermission = (permission) => (req, res, next) => {
  if (!req.user) return sendError(res, 401, 'AUTH_005', 'Not authenticated');
  if (!req.user.permissions?.includes(permission)) {
    return sendError(res, 403, 'AUTH_FORBIDDEN', `Missing permission: ${permission}`);
  }
  next();
};

module.exports = { authenticateJWT, requireAdmin, requirePermission };
