const router = require('express').Router();
const { authenticate } = require('../../middleware/auth.middleware');
const controller = require('./user.controller');

router.use(authenticate);

router.get('/search',    controller.searchUsers);
router.get('/me', controller.getMe);
router.patch('/me', controller.updateProfile);
router.get('/me/matches', controller.getMatchHistory);
router.get('/me/friends', controller.getFriends);
router.get('/me/friend-requests', controller.getPendingRequests);
router.post('/friends/:userId', controller.sendFriendRequest);
router.post('/friends/:userId/accept', controller.acceptFriendRequest);
router.post('/friends/:userId/decline', controller.declineFriendRequest);
router.get('/notifications', controller.getNotifications);
router.patch('/notifications/read', controller.markNotificationsRead);

module.exports = router;
