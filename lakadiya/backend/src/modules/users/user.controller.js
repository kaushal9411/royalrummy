const userService = require('./user.service');

const getMe = async (req, res, next) => {
  try {
    const profile = await userService.getProfile(req.user.id);
    res.json(profile);
  } catch (err) { next(err); }
};

const updateProfile = async (req, res, next) => {
  try {
    const updated = await userService.updateProfile(req.user.id, req.body);
    res.json(updated);
  } catch (err) { next(err); }
};

const getMatchHistory = async (req, res, next) => {
  try {
    const { limit = 20, offset = 0 } = req.query;
    const history = await userService.getMatchHistory(req.user.id, Number(limit), Number(offset));
    res.json(history);
  } catch (err) { next(err); }
};

const sendFriendRequest = async (req, res, next) => {
  try {
    await userService.sendFriendRequest(req.user.id, req.params.userId);
    res.json({ message: 'Friend request sent' });
  } catch (err) { next(err); }
};

const acceptFriendRequest = async (req, res, next) => {
  try {
    await userService.acceptFriendRequest(req.user.id, req.params.userId);
    res.json({ message: 'Friend request accepted' });
  } catch (err) { next(err); }
};

const getFriends = async (req, res, next) => {
  try {
    const friends = await userService.getFriends(req.user.id);
    res.json(friends);
  } catch (err) { next(err); }
};

const getNotifications = async (req, res, next) => {
  try {
    const notifs = await userService.getNotifications(req.user.id);
    res.json(notifs);
  } catch (err) { next(err); }
};

const markNotificationsRead = async (req, res, next) => {
  try {
    await userService.markNotificationsRead(req.user.id);
    res.json({ message: 'Marked as read' });
  } catch (err) { next(err); }
};

const searchUsers = async (req, res, next) => {
  try {
    const { q = '', limit = 30 } = req.query;
    const users = await userService.searchUsers(req.user.id, q, Math.min(Number(limit), 50));
    res.json(users);
  } catch (err) { next(err); }
};

module.exports = {
  getMe, updateProfile, getMatchHistory,
  sendFriendRequest, acceptFriendRequest, getFriends,
  getNotifications, markNotificationsRead,
  searchUsers,
};
