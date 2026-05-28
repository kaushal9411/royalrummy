const router = require('express').Router();
const { authenticateAdmin } = require('../../middleware/auth.middleware');
const service = require('./admin.service');
const { sendAdminBroadcast, getBroadcastHistory } = require('../notifications/notification.service');
const { getSettings, updateSettings } = require('./settings.service');

router.use(authenticateAdmin);

router.get('/dashboard', async (req, res, next) => {
  try { res.json(await service.getDashboardStats()); } catch (e) { next(e); }
});

router.get('/users', async (req, res, next) => {
  try {
    const { page, limit, search, banned } = req.query;
    const data = await service.getUsers({
      page:   Number(page) || 1,
      limit:  Math.min(Number(limit) || 20, 100),
      search: search || '',
      banned: banned !== undefined ? banned === 'true' : null,
    });
    res.json(data);
  } catch (e) { next(e); }
});

router.post('/users/:userId/ban', async (req, res, next) => {
  try {
    await service.banUser(req.params.userId, req.body.reason || 'Policy violation');
    res.json({ message: 'User banned' });
  } catch (e) { next(e); }
});

router.post('/users/:userId/unban', async (req, res, next) => {
  try {
    await service.unbanUser(req.params.userId);
    res.json({ message: 'User unbanned' });
  } catch (e) { next(e); }
});

router.get('/matches', async (req, res, next) => {
  try {
    const { page, limit, status } = req.query;
    const data = await service.getMatches({
      page: Number(page) || 1,
      limit: Math.min(Number(limit) || 20, 100),
      status: status || '',
    });
    res.json(data);
  } catch (e) { next(e); }
});

router.get('/analytics', async (req, res, next) => {
  try { res.json(await service.getAnalytics()); } catch (e) { next(e); }
});

// ── Notification broadcast ────────────────────────────────────────────────────
router.post('/notifications/broadcast', async (req, res, next) => {
  try {
    const { title, body, type = 'GENERAL', data = {} } = req.body;
    if (!title?.trim() || !body?.trim())
      return res.status(400).json({ error: 'title and body are required' });
    const result = await sendAdminBroadcast(title.trim(), body.trim(), type, data);
    res.json({ success: true, sent: result.sent });
  } catch (e) { next(e); }
});

router.get('/notifications/history', async (req, res, next) => {
  try {
    const limit = Math.min(Number(req.query.limit) || 50, 200);
    const logs = await getBroadcastHistory(limit);
    res.json(logs);
  } catch (e) { next(e); }
});

// ── Platform settings ─────────────────────────────────────────────────────────
router.get('/settings', async (req, res, next) => {
  try { res.json(await getSettings()); } catch (e) { next(e); }
});

router.patch('/settings', async (req, res, next) => {
  try {
    const updated = await updateSettings(req.body);
    res.json(updated);
  } catch (e) { next(e); }
});

module.exports = router;
