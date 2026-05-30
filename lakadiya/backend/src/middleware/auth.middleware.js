const jwt = require('jsonwebtoken');
const { query } = require('../config/database');

const authenticate = async (req, res, next) => {
  const authHeader = req.headers.authorization;
  if (!authHeader || !authHeader.startsWith('Bearer ')) {
    return res.status(401).json({ message: 'No token provided' });
  }

  const token = authHeader.split(' ')[1];
  try {
    const decoded = jwt.verify(token, process.env.JWT_SECRET);
    const result = await query('SELECT id, username, email, is_banned FROM users WHERE id = $1', [decoded.userId]);
    if (!result.rows.length) return res.status(401).json({ message: 'User not found' });
    if (result.rows[0].is_banned) return res.status(403).json({ message: 'Account banned' });
    req.user = result.rows[0];
    next();
  } catch (err) {
    return res.status(401).json({ message: 'Invalid token' });
  }
};

const authenticateAdmin = async (req, res, next) => {
  const authHeader = req.headers.authorization;
  if (!authHeader || !authHeader.startsWith('Bearer ')) {
    return res.status(401).json({ message: 'No token provided' });
  }
  const token = authHeader.split(' ')[1];
  try {
    const decoded = jwt.verify(token, process.env.JWT_SECRET);
    if (!decoded.isAdmin) return res.status(403).json({ message: 'Forbidden' });
    req.admin = decoded;
    next();
  } catch {
    return res.status(401).json({ message: 'Invalid token' });
  }
};

// Same as authenticateAdmin but also accepts ?token= query param
// Used for <img> / <a> endpoints where setting headers is not possible
const authenticateAdminFile = (req, res, next) => {
  const raw = req.headers.authorization?.replace('Bearer ', '') || req.query.token;
  if (!raw) return res.status(401).json({ message: 'No token provided' });
  try {
    const decoded = jwt.verify(raw, process.env.JWT_SECRET);
    if (!decoded.isAdmin) return res.status(403).end();
    req.admin = decoded;
    next();
  } catch {
    return res.status(401).end();
  }
};

const authenticateSocket = (socket, next) => {
  const token = socket.handshake.auth?.token;
  if (!token) return next(new Error('No token'));
  try {
    const decoded = jwt.verify(token, process.env.JWT_SECRET);
    socket.userId = decoded.userId;
    socket.username = decoded.username;
    next();
  } catch {
    next(new Error('Invalid token'));
  }
};

module.exports = { authenticate, authenticateAdmin, authenticateAdminFile, authenticateSocket };
