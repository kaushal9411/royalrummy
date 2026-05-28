const service = require('./message.service');

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
