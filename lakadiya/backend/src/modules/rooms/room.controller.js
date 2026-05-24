const roomService = require('./room.service');

const createRoom = async (req, res, next) => {
  try {
    const room = await roomService.createRoom(req.user.id, req.body.isPrivate);
    res.status(201).json(room);
  } catch (err) { next(err); }
};

const joinRoom = async (req, res, next) => {
  try {
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

module.exports = { createRoom, joinRoom, getRoomDetails, leaveRoom, addBot, getPublicRooms };
