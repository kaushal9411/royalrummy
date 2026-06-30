const router  = require('express').Router();
const path    = require('path');
const fs      = require('fs');
const multer  = require('multer');
const { authenticateAdmin, authenticateAdminFile } = require('../../middleware/auth.middleware');
const { query } = require('../../config/database');
const service = require('./admin.service');

// ── APK builds upload storage ─────────────────────────────────────────────────
const BUILDS_DIR = path.join(__dirname, '../../../../uploads/builds');
fs.mkdirSync(BUILDS_DIR, { recursive: true });

const buildsStorage = multer.diskStorage({
  destination: (_req, _file, cb) => cb(null, BUILDS_DIR),
  filename:    (_req, file, cb) => {
    const ts   = Date.now();
    const safe = file.originalname.replace(/[^a-zA-Z0-9._-]/g, '_');
    cb(null, `${ts}_${safe}`);
  },
});
const uploadApk = multer({
  storage: buildsStorage,
  limits:  { fileSize: 200 * 1024 * 1024 }, // 200 MB
  fileFilter: (_req, file, cb) => {
    if (file.mimetype === 'application/vnd.android.package-archive' ||
        file.originalname.endsWith('.apk') ||
        file.originalname.endsWith('.aab')) {
      cb(null, true);
    } else {
      cb(new Error('Only .apk or .aab files are allowed'));
    }
  },
});

// Ensure builds table exists
query(`
  CREATE TABLE IF NOT EXISTS app_builds (
    id          SERIAL PRIMARY KEY,
    version     VARCHAR(50)  NOT NULL,
    build_num   INTEGER      NOT NULL DEFAULT 0,
    platform    VARCHAR(20)  NOT NULL DEFAULT 'android',
    filename    TEXT         NOT NULL,
    filepath    TEXT         NOT NULL,
    filesize    BIGINT       NOT NULL DEFAULT 0,
    notes       TEXT,
    uploaded_by TEXT,
    created_at  TIMESTAMPTZ  DEFAULT NOW()
  )
`).catch(() => {});
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

// ── APK build download (uses ?token= so <a download> works without custom headers) ─
router.get('/builds/:id/download', authenticateAdminFile, async (req, res, next) => {
  try {
    const { rows } = await query('SELECT * FROM app_builds WHERE id = $1', [req.params.id]);
    if (!rows.length) return res.status(404).json({ message: 'Build not found' });
    const build = rows[0];
    if (!fs.existsSync(build.filepath)) return res.status(404).json({ message: 'File not found on server' });
    res.download(build.filepath, `lakadiya-v${build.version}-${build.build_num}.apk`);
  } catch (e) { next(e); }
});

// All routes below this line require a valid admin JWT in the Authorization header
router.use(authenticateAdmin);

router.get('/dashboard', async (req, res, next) => {
  try { res.json(await service.getDashboardStats()); } catch (e) { next(e); }
});

// ── App Builds ────────────────────────────────────────────────────────────────
router.get('/builds', async (req, res, next) => {
  try {
    const { rows } = await query(
      `SELECT id, version, build_num, platform, filename, filesize, notes, uploaded_by, created_at
       FROM app_builds ORDER BY created_at DESC`
    );
    res.json(rows);
  } catch (e) { next(e); }
});

router.post('/builds/upload', uploadApk.single('apk'), async (req, res, next) => {
  try {
    if (!req.file) return res.status(400).json({ message: 'No file uploaded' });
    const { version = '1.0.0', build_num = 0, notes = '', platform = 'android' } = req.body;
    const { rows } = await query(
      `INSERT INTO app_builds (version, build_num, platform, filename, filepath, filesize, notes, uploaded_by)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8) RETURNING *`,
      [version, parseInt(build_num), platform, req.file.originalname, req.file.path, req.file.size, notes, req.admin?.username || 'admin']
    );
    res.json({ success: true, build: rows[0] });
  } catch (e) { next(e); }
});

router.delete('/builds/:id', async (req, res, next) => {
  try {
    const { rows } = await query('SELECT * FROM app_builds WHERE id = $1', [req.params.id]);
    if (!rows.length) return res.status(404).json({ message: 'Build not found' });
    if (fs.existsSync(rows[0].filepath)) fs.unlinkSync(rows[0].filepath);
    await query('DELETE FROM app_builds WHERE id = $1', [req.params.id]);
    res.json({ success: true });
  } catch (e) { next(e); }
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

// Full match detail — meta + player-wise breakdown (score, position, winnings)
router.get('/matches/:matchId', async (req, res, next) => {
  try {
    const { matchId } = req.params;
    const metaRes = await query(
      `SELECT m.id, m.status, m.created_at, m.finished_at, m.winner_id, m.total_rounds,
              r.id AS room_id, r.code AS room_code, r.bet_amount, r.is_private,
              wu.username AS winner_name,
              (SELECT COALESCE(SUM(amount), 0)::float FROM game_bets WHERE match_id = m.id) AS total_pot
       FROM matches m
       JOIN rooms r ON r.id = m.room_id
       LEFT JOIN users wu ON wu.id = m.winner_id
       WHERE m.id = $1`,
      [matchId],
    );
    if (!metaRes.rows.length) return res.status(404).json({ message: 'Match not found' });
    const meta = metaRes.rows[0];

    const playersRes = await query(
      `SELECT mp.seat, mp.user_id, mp.is_bot, mp.final_score::float AS final_score,
              u.username, u.avatar_url, u.level
       FROM match_players mp
       LEFT JOIN users u ON u.id = mp.user_id
       WHERE mp.match_id = $1
       ORDER BY mp.final_score DESC, mp.seat`,
      [matchId],
    );

    const players = playersRes.rows.map((p, i) => ({
      seat:        p.seat,
      user_id:     p.user_id,
      is_bot:      p.is_bot,
      name:        p.is_bot ? 'Bot' : (p.username || 'Unknown'),
      avatar_url:  p.is_bot ? null : p.avatar_url,
      level:       p.level,
      final_score: p.final_score,
      position:    i + 1,                 // 1 = highest score = winner
      is_winner:   i === 0,
      won_amount:  (i === 0 && !p.is_bot && meta.total_pot > 0) ? meta.total_pot : 0,
    }));

    res.json({ match: meta, players });
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
              r.created_at,
              -- live player count
              (SELECT COUNT(*) FROM room_players rp WHERE rp.room_id = r.id)::int AS player_count,
              -- ordered list of player names (bots labelled)
              (SELECT COALESCE(json_agg(
                        json_build_object(
                          'name',  CASE WHEN rp.is_bot
                                        THEN 'Bot (' || COALESCE(rp.bot_level,'medium') || ')'
                                        ELSE pu.username END,
                          'is_bot', rp.is_bot,
                          'seat',   rp.seat
                        ) ORDER BY rp.seat), '[]'::json)
               FROM room_players rp
               LEFT JOIN users pu ON pu.id = rp.user_id
               WHERE rp.room_id = r.id) AS players,
              -- winner + amount won + match id (latest match for this room)
              m.match_id,
              m.winner_name,
              m.won_amount
       FROM rooms r
       JOIN users u ON u.id = r.host_id
       LEFT JOIN LATERAL (
         SELECT mm.id AS match_id,
                wu.username AS winner_name,
                (SELECT COALESCE(SUM(gb.amount), 0)::float
                   FROM game_bets gb WHERE gb.match_id = mm.id) AS won_amount
         FROM matches mm
         LEFT JOIN users wu ON wu.id = mm.winner_id
         WHERE mm.room_id = r.id
         ORDER BY mm.created_at DESC
         LIMIT 1
       ) m ON TRUE
       ${status ? 'WHERE r.status = $3' : ''}
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

// Hard-delete a room — kicks everyone and removes the room (cascades players/match)
router.delete('/rooms/:roomId', async (req, res, next) => {
  try {
    const { roomId } = req.params;
    const { rows } = await query(
      'SELECT user_id FROM room_players WHERE room_id = $1 AND is_bot = FALSE',
      [roomId],
    );
    try {
      const io = getIO();
      for (const { user_id } of rows) {
        const socketId = userSockets.get(user_id);
        if (socketId) {
          io.to(socketId).emit('kicked', { reason: 'Room deleted by admin', roomId });
          userSockets.delete(user_id);
        }
      }
      io.emit('lobby_updated');
    } catch (_) {}
    await query('DELETE FROM rooms WHERE id = $1', [roomId]); // FK cascade clears the rest
    res.json({ message: 'Room deleted' });
  } catch (e) { next(e); }
});

module.exports = router;
