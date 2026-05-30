const roomService = require('./room.service');
const { isExcluded, checkSpendLimit } = require('../responsible_gaming/responsible_gaming.service');

const _checkResponsibleGaming = async (userId, betAmount) => {
  if (await isExcluded(userId)) {
    throw { status: 403, message: 'You have self-excluded from real-money games. Manage this in Settings → Responsible Gaming.' };
  }
  if (betAmount > 0) {
    for (const period of ['daily', 'weekly', 'monthly']) {
      const { exceeded, used, limit } = await checkSpendLimit(userId, period);
      if (exceeded) {
        throw { status: 403, message: `You have reached your ${period} spending limit (used ₹${used} of ₹${limit}). Update your limits in Settings → Responsible Gaming.` };
      }
    }
  }
};

const createRoom = async (req, res, next) => {
  try {
    const betAmount = req.body.betAmount ?? 0;
    await _checkResponsibleGaming(req.user.id, betAmount);
    const room = await roomService.createRoom(req.user.id, req.body.isPrivate, betAmount);
    res.status(201).json(room);
  } catch (err) { next(err); }
};

const joinRoom = async (req, res, next) => {
  try {
    // Pass betAmount=1 so limit check runs (limits are based on cumulative past spending)
    await _checkResponsibleGaming(req.user.id, 1);
    const room = await roomService.joinRoom(req.user.id, req.params.code);
    res.json(room);
  } catch (err) { next(err); }
};

const getRoomDetails = async (req, res, next) => {
  try {
    const room = await roomService.getRoomDetails(req.params.roomId);
    res.json(room);
  } catch (err) { next(err); }
};

const leaveRoom = async (req, res, next) => {
  try {
    await roomService.leaveRoom(req.user.id, req.params.roomId);
    res.json({ message: 'Left room' });
  } catch (err) { next(err); }
};

const addBot = async (req, res, next) => {
  try {
    const room = await roomService.addBot(req.user.id, req.params.roomId, req.body.level);
    res.json(room);
  } catch (err) { next(err); }
};

const getPublicRooms = async (req, res, next) => {
  try {
    const rooms = await roomService.getPublicRooms();
    res.json(rooms);
  } catch (err) { next(err); }
};

const resetBet = async (req, res, next) => {
  try {
    await roomService.resetBet(req.user.id, req.params.roomId);
    res.json({ message: 'Bet reset to free' });
  } catch (err) { next(err); }
};

module.exports = { createRoom, joinRoom, getRoomDetails, leaveRoom, addBot, getPublicRooms, resetBet };
