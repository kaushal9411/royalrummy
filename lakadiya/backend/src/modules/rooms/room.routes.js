const router = require('express').Router();
const { authenticate } = require('../../middleware/auth.middleware');
const controller = require('./room.controller');

router.use(authenticate);

router.get('/public', controller.getPublicRooms);
router.get('/my', controller.getMyActiveRooms);
router.post('/', controller.createRoom);
router.get('/:roomId', controller.getRoomDetails);
router.post('/join/:code', controller.joinRoom);
router.delete('/:roomId/leave', controller.leaveRoom);
router.delete('/:roomId', controller.deleteRoom);
router.post('/:roomId/bot', controller.addBot);
router.patch('/:roomId/reset-bet', controller.resetBet);

module.exports = router;
