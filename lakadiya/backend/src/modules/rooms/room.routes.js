const router = require('express').Router();
const { authenticate } = require('../../middleware/auth.middleware');
const controller = require('./room.controller');

router.use(authenticate);

router.get('/public', controller.getPublicRooms);
router.post('/', controller.createRoom);
router.get('/:roomId', controller.getRoomDetails);
router.post('/join/:code', controller.joinRoom);
router.delete('/:roomId/leave', controller.leaveRoom);
router.post('/:roomId/bot', controller.addBot);

module.exports = router;
