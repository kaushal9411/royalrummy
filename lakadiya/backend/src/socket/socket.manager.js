const { Server } = require('socket.io');
const { authenticateSocket } = require('../middleware/auth.middleware');
const { registerGameSocket } = require('./game.socket');
const logger = require('../config/logger');

let io;

function initSocket(server) {
  io = new Server(server, {
    cors: {
      origin: process.env.ALLOWED_ORIGINS?.split(',') || '*',
      methods: ['GET', 'POST'],
    },
    pingTimeout: 30000,
    pingInterval: 10000,
  });

  io.use(authenticateSocket);

  io.on('connection', (socket) => {
    logger.debug(`Socket connected: ${socket.id} user:${socket.userId}`);
    registerGameSocket(io, socket);

    socket.on('disconnect', (reason) => {
      logger.debug(`Socket disconnected: ${socket.id} reason:${reason}`);
    });
  });

  return io;
}

function getIO() {
  if (!io) throw new Error('Socket.IO not initialized');
  return io;
}

module.exports = { initSocket, getIO };
