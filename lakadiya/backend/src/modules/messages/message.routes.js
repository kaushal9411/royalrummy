const router = require('express').Router();
const { authenticate } = require('../../middleware/auth.middleware');
const { messageLimiter } = require('../../middleware/rate-limit.middleware');
const ctrl = require('./message.controller');

router.use(authenticate);

router.get('/',               ctrl.getConversationList);
router.get('/unread',         ctrl.getUnread);
router.get('/:userId',        ctrl.getConversation);
router.post('/:userId',       messageLimiter, ctrl.sendMessage); // per-user anti-spam
router.patch('/:userId/read', ctrl.markRead);

module.exports = router;
