const express = require('express');
const multer = require('multer');
const path = require('path');
const { authenticate, authenticateAdmin } = require('../../middleware/auth.middleware');
const { submitKyc, getKycStatus, approveKyc, rejectKyc, listPendingKyc } = require('./kyc.service');

const router = express.Router();

const storage = multer.diskStorage({
  destination: (req, file, cb) => {
    const dir = path.join(__dirname, '../../../../uploads/kyc');
    require('fs').mkdirSync(dir, { recursive: true });
    cb(null, dir);
  },
  filename: (req, file, cb) => {
    const ext = path.extname(file.originalname);
    cb(null, `${req.user.id}_${file.fieldname}_${Date.now()}${ext}`);
  },
});
const upload = multer({
  storage,
  limits: { fileSize: 5 * 1024 * 1024 }, // 5 MB
  fileFilter: (req, file, cb) => {
    const allowed = ['.jpg', '.jpeg', '.png', '.pdf'];
    cb(null, allowed.includes(path.extname(file.originalname).toLowerCase()));
  },
});

// User: submit KYC documents
router.post('/submit', authenticate, upload.fields([
  { name: 'pan_doc', maxCount: 1 },
  { name: 'selfie', maxCount: 1 },
]), async (req, res, next) => {
  try {
    const { pan_number, full_name } = req.body;
    if (!pan_number || !full_name) return res.status(400).json({ message: 'PAN number and full name required' });
    const panDocPath = req.files?.pan_doc?.[0]?.path || null;
    const selfiePath = req.files?.selfie?.[0]?.path || null;
    if (!panDocPath || !selfiePath) return res.status(400).json({ message: 'Both PAN card and selfie documents are required' });
    const result = await submitKyc(req.user.id, { panNumber: pan_number, fullName: full_name, panDocPath, selfiePath });
    res.json({ message: 'KYC submitted for review', data: result });
  } catch (e) { next(e); }
});

// User: check their KYC status
router.get('/status', authenticate, async (req, res, next) => {
  try {
    const status = await getKycStatus(req.user.id);
    res.json(status || { status: 'not_submitted' });
  } catch (e) { next(e); }
});

// Admin: list pending KYC submissions
router.get('/pending', authenticateAdmin, async (req, res, next) => {
  try {
    const list = await listPendingKyc();
    res.json(list);
  } catch (e) { next(e); }
});

// Admin: approve KYC
router.post('/:kycId/approve', authenticateAdmin, async (req, res, next) => {
  try {
    await approveKyc(req.params.kycId);
    res.json({ message: 'KYC approved' });
  } catch (e) { next(e); }
});

// Admin: reject KYC
router.post('/:kycId/reject', authenticateAdmin, async (req, res, next) => {
  try {
    const { remark } = req.body;
    await rejectKyc(req.params.kycId, remark);
    res.json({ message: 'KYC rejected' });
  } catch (e) { next(e); }
});

module.exports = router;
