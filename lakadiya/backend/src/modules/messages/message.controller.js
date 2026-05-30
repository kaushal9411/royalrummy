const service = require('./message.service');
const { getIO } = require('../../socket/socket.manager');
const { sendNotification } = require('../notifications/notification.service');

const getConversation = async (req, res, next) => {
  try {
    const { userId } = req.params;
    const { limit = 50, before } = req.query;
    const msgs = await service.getConversation(
      req.user.id, userId, Math.min(Number(limit), 100), before ? Number(before) : null
    );
    res.json(msgs);
  } catch (err) { next(err); }
};

const sendMessage = async (req, res, next) => {
  try {
    const { userId } = req.params;
    const { text } = req.body;
    if (!text?.trim()) return res.status(400).json({ error: 'Message text required' });
    
    const msg = await service.sendMessage(req.user.id, userId, text);
    
    // Emit socket event to recipient for real-time delivery
    try {
      const io = getIO();
      io.to(`user:${userId}`).emit('private_message', {
        id: msg.id,
        sender_id: msg.sender_id,
        sender_name: req.user.username,
        receiver_id: msg.receiver_id,
        text: msg.text,
        created_at: msg.created_at,
      });
    } catch (socketErr) {
      console.log('Socket emit error:', socketErr.message);
    }
    
    // Send FCM push notification to recipient
    try {
      await sendNotification(
        userId,
        req.user.username,
        msg.text.substring(0, 100),
        {
          type:        'MESSAGE_RECEIVED',
          senderId:    req.user.id,
          senderName:  req.user.username,
          messageText: msg.text,
        },
        'default_channel'
      );
    } catch (notifErr) {
      console.log('Notification send error:', notifErr.message);
    }
    
    res.json(msg);
  } catch (err) { next(err); }
};

const markRead = async (req, res, next) => {
  try {
    await service.markRead(req.user.id, req.params.userId);
    res.json({ ok: true });
  } catch (err) { next(err); }
};

const getConversationList = async (req, res, next) => {
  try {
    res.json(await service.getConversationList(req.user.id));
  } catch (err) { next(err); }
};

const getUnread = async (req, res, next) => {
  try {
    res.json({ count: await service.getTotalUnread(req.user.id) });
  } catch (err) { next(err); }
};

module.exports = { getConversation, sendMessage, markRead, getConversationList, getUnread };
