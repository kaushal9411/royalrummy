const router = require('express').Router();
const { authenticateAdmin, authenticateAdminFile } = require('../../middleware/auth.middleware');
const { query } = require('../../config/database');
const service = require('./admin.service');
const { sendAdminBroadcast, getBroadcastHistory } = require('../notifications/notification.service');
const { getSettings, updateSettings } = require('./settings.service');
const { listCredentials, setCredential, deleteCredential } = require('../credentials/credentials.service');
const { approveKyc, rejectKyc, listPendingKyc } = require('../kyc/kyc.service');

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

// ── KYC document serving ─────────────────────────────────────────────────────
// Uses ?token= so <img> tags can include the admin JWT without fetch()
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

    res.sendFile(filePath);
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

module.exports = router;
