const router = require('express').Router();
const path   = require('path');
const { authenticateAdmin, authenticateAdminFile } = require('../../middleware/auth.middleware');
const { query } = require('../../config/database');
const service = require('./admin.service');
const { sendAdminBroadcast, getBroadcastHistory } = require('../notifications/notification.service');
const { getSettings, updateSettings } = require('./settings.service');
const { listCredentials, setCredential, deleteCredential } = require('../credentials/credentials.service');
const { approveKyc, rejectKyc, listPendingKyc } = require('../kyc/kyc.service');
const { setSelfExclusion, updateSettings: updateRgSettings } = require('../responsible_gaming/responsible_gaming.service');
const { userSockets } = require('../../socket/game.socket');
const { getIO } = require('../../socket/socket.manager');

// ── KYC document file serving ─────────────────────────────────────────────────
// MUST be registered BEFORE router.use(authenticateAdmin) because <img> tags
// cannot send Authorization headers — authenticateAdminFile accepts ?token= instead.
router.get('/kyc/:kycId/document/:docType', authenticateAdminFile, async (req, res, next) => {
  try {
    const { kycId, docType } = req.params;
    if (!['pan_doc', 'selfie'].includes(docType))
      return res.status(400).json({ message: 'Invalid doc type' });

    const { rows } = await query(
      'SELECT pan_doc_path, selfie_path FROM kyc_submissions WHERE id = $1',
      [kycId]
    );
    if (!rows.length) return res.status(404).end();

    const filePath = docType === 'pan_doc' ? rows[0].pan_doc_path : rows[0].selfie_path;
    if (!filePath) return res.status(404).json({ message: 'Document not uploaded' });

    // Ensure absolute path — multer stores absolute paths but guard for safety
    const absPath = path.isAbsolute(filePath) ? filePath : path.resolve(filePath);

    // Derive MIME type from extension so browser renders inline
    const ext  = path.extname(absPath).toLowerCase();
    const mime = ext === '.pdf' ? 'application/pdf' : ext === '.png' ? 'image/png' : 'image/jpeg';
    res.setHeader('Content-Type', mime);
    res.sendFile(absPath);
  } catch (e) { next(e); }
});

// All routes below this line require a valid admin JWT in the Authorization header
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

// Full compliance detail for one user
router.get('/users/:userId/detail', async (req, res, next) => {
  try { res.json(await service.getUserDetail(req.params.userId)); } catch (e) { next(e); }
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

// ── Responsible gaming (admin override) ──────────────────────────────────────
// Lift a user's self-exclusion — admin can remove it on user's behalf
router.post('/users/:userId/lift-exclusion', async (req, res, next) => {
  try {
    await setSelfExclusion(req.params.userId, 0); // days=0 clears exclusion
    res.json({ message: 'Self-exclusion lifted' });
  } catch (e) { next(e); }
});


// ── KYC management ────────────────────────────────────────────────────────────
router.get('/kyc/pending', async (req, res, next) => {
  try { res.json(await listPendingKyc()); } catch (e) { next(e); }
});

router.post('/kyc/:kycId/approve', async (req, res, next) => {
  try { await approveKyc(req.params.kycId); res.json({ message: 'KYC approved' }); }
  catch (e) { next(e); }
});

router.post('/kyc/:kycId/reject', async (req, res, next) => {
  try {
    await rejectKyc(req.params.kycId, req.body.remark || 'Documents not acceptable');
    res.json({ message: 'KYC rejected' });
  } catch (e) { next(e); }
});

// ── Credentials management ────────────────────────────────────────────────────
// List all stored credentials (values are masked — never returns plaintext)
router.get('/credentials', async (req, res, next) => {
  try { res.json(await listCredentials()); } catch (e) { next(e); }
});

// Create or update a credential
router.post('/credentials', async (req, res, next) => {
  try {
    const { key_name, value } = req.body;
    if (!key_name?.trim() || !value?.trim())
      return res.status(400).json({ message: 'key_name and value are required' });
    await setCredential(key_name.trim(), value.trim());
    res.json({ message: 'Credential saved', key_name: key_name.trim() });
  } catch (e) { next(e); }
});

// Delete a credential by key name
router.delete('/credentials/:keyName', async (req, res, next) => {
  try {
    const deleted = await deleteCredential(req.params.keyName);
    if (!deleted) return res.status(404).json({ message: 'Credential not found' });
    res.json({ message: 'Credential deleted' });
  } catch (e) { next(e); }
});

// ── Room management ───────────────────────────────────────────────────────────

const VALID_STATUSES = ['waiting', 'playing', 'finished'];

router.get('/rooms', async (req, res, next) => {
  try {
    const limit  = Math.min(Number(req.query.limit) || 200, 500);
    const offset = Number(req.query.offset) || 0;
    const status = VALID_STATUSES.includes(req.query.status) ? req.query.status : null;

    const params = status ? [limit, offset, status] : [limit, offset];
    const { rows } = await query(
      `SELECT r.id, r.code, r.status, r.is_private, r.bet_amount, r.host_id,
              u.username AS host_name,
              COUNT(rp.seat)::int AS player_count,
              r.created_at, r.started_at, r.finished_at
       FROM rooms r
       JOIN users u ON u.id = r.host_id
       LEFT JOIN room_players rp ON rp.room_id = r.id
       ${status ? 'WHERE r.status = $3' : ''}
       GROUP BY r.id, r.code, r.status, r.is_private, r.bet_amount, r.host_id,
                u.username, r.created_at, r.started_at, r.finished_at
       ORDER BY r.created_at DESC
       LIMIT $1 OFFSET $2`,
      params,
    );
    const { rows: ct } = await query(
      `SELECT COUNT(*)::int AS total FROM rooms${status ? ' WHERE status = $1' : ''}`,
      status ? [status] : [],
    );
    res.json({ rooms: rows, total: ct[0].total });
  } catch (e) { next(e); }
});

router.get('/rooms/:roomId/players', async (req, res, next) => {
  try {
    const { rows } = await query(
      `SELECT rp.seat, rp.is_bot, rp.bot_level,
              u.id AS user_id, u.username, u.avatar_url, u.level
       FROM room_players rp
       LEFT JOIN users u ON u.id = rp.user_id
       WHERE rp.room_id = $1
       ORDER BY rp.seat`,
      [req.params.roomId],
    );
    const players = rows.map(p => ({
      ...p,
      is_online: p.is_bot ? false : userSockets.has(p.user_id),
    }));
    res.json(players);
  } catch (e) { next(e); }
});

// Kick one player out of a room (removes seat, disconnects socket if online)
router.delete('/rooms/:roomId/players/:userId', async (req, res, next) => {
  try {
    const { roomId, userId } = req.params;
    await query(
      'DELETE FROM room_players WHERE room_id = $1 AND user_id = $2',
      [roomId, userId],
    );
    const socketId = userSockets.get(userId);
    if (socketId) {
      try { getIO().to(socketId).emit('kicked', { reason: 'Removed by admin', roomId }); } catch (_) {}
      userSockets.delete(userId);
    }
    res.json({ message: 'Player kicked' });
  } catch (e) { next(e); }
});

// Force-close a room — removes all players and marks it finished
router.patch('/rooms/:roomId/close', async (req, res, next) => {
  try {
    const { roomId } = req.params;
    const { rows } = await query(
      'SELECT user_id FROM room_players WHERE room_id = $1 AND is_bot = FALSE',
      [roomId],
    );
    await query('DELETE FROM room_players WHERE room_id = $1', [roomId]);
    await query("UPDATE rooms SET status = 'finished' WHERE id = $1", [roomId]);
    try {
      const io = getIO();
      for (const { user_id } of rows) {
        const socketId = userSockets.get(user_id);
        if (socketId) {
          io.to(socketId).emit('kicked', { reason: 'Room closed by admin', roomId });
          userSockets.delete(user_id);
        }
      }
    } catch (_) {}
    res.json({ message: 'Room closed' });
  } catch (e) { next(e); }
});

module.exports = router;
