const router = require('express').Router();
const { authenticate } = require('../../middleware/auth.middleware');
const controller = require('./user.controller');

router.use(authenticate);

router.get('/me', controller.getMe);
router.patch('/me', controller.updateProfile);
router.get('/me/matches', controller.getMatchHistory);
router.get('/me/friends', controller.getFriends);
router.post('/friends/:userId', controller.sendFriendRequest);
router.patch('/friends/:userId/accept', controller.acceptFriendRequest);
router.get('/notifications', controller.getNotifications);
router.patch('/notifications/read', controller.markNotificationsRead);

module.exports = router;
