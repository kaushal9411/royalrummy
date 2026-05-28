const userService = require('./user.service');
const { getIO } = require('../../socket/socket.manager');
const { sendNotification } = require('../notifications/notification.service');

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
    
    const recipientId = req.params.userId;
    
    // Emit socket event to recipient for real-time update
    try {
      const io = getIO();
      io.to(`user:${recipientId}`).emit('friend_request', {
        fromUserId: req.user.id,
        fromUsername: req.user.username,
      });
    } catch (socketErr) {
      console.log('Socket emit error:', socketErr.message);
    }
    
    // Send FCM push notification to recipient
    try {
      await sendNotification(
        recipientId,
        'Friend Request',
        `${req.user.username} sent you a friend request`,
        {
          type: 'friend_request',
          fromUserId: req.user.id,
          fromUsername: req.user.username,
          action: 'FRIEND_REQUEST',
        },
        'social_channel'
      );
    } catch (notifErr) {
      console.log('Notification send error:', notifErr.message);
    }
    
    res.json({ message: 'Friend request sent' });
  } catch (err) { next(err); }
};

const acceptFriendRequest = async (req, res, next) => {
  try {
    const requesterId = req.params.userId;
    await userService.acceptFriendRequest(req.user.id, requesterId);
    
    // Emit socket event to the friend who sent the request
    try {
      const io = getIO();
      io.to(`user:${requesterId}`).emit('friend_accepted', {
        userId: req.user.id,
        username: req.user.username,
      });
    } catch (socketErr) {
      console.log('Socket emit error:', socketErr.message);
    }
    
    // Send FCM push notification to requester
    try {
      await sendNotification(
        requesterId,
        'Friend Request Accepted',
        `${req.user.username} accepted your friend request`,
        {
          type: 'friend_accepted',
          userId: req.user.id,
          username: req.user.username,
          action: 'FRIEND_ACCEPTED',
        },
        'social_channel'
      );
    } catch (notifErr) {
      console.log('Notification send error:', notifErr.message);
    }
    
    res.json({ message: 'Friend request accepted' });
  } catch (err) { next(err); }
};

const declineFriendRequest = async (req, res, next) => {
  try {
    const requesterId = req.params.userId;
    await userService.declineFriendRequest(req.user.id, requesterId);
    
    // Send FCM push notification to requester
    try {
      await sendNotification(
        requesterId,
        'Friend Request Declined',
        `${req.user.username} declined your friend request`,
        {
          type: 'friend_declined',
          userId: req.user.id,
          username: req.user.username,
          action: 'FRIEND_DECLINED',
        },
        'social_channel'
      );
    } catch (notifErr) {
      console.log('Notification send error:', notifErr.message);
    }
    
    res.json({ message: 'Friend request declined' });
  } catch (err) { next(err); }
};

const getPendingRequests = async (req, res, next) => {
  try {
    const requests = await userService.getPendingRequests(req.user.id);
    res.json(requests);
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
  sendFriendRequest, acceptFriendRequest, declineFriendRequest, getPendingRequests, getFriends,
  getNotifications, markNotificationsRead,
  searchUsers,
};
