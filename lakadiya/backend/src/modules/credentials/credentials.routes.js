const express = require('express');
const { authenticate, authenticateAdmin } = require('../../middleware/auth.middleware');
const { getPublicAppKeys, setCredential } = require('./credentials.service');

const router = express.Router();

// Mobile app fetches Razorpay publishable key (no secret) on startup
router.get('/app-keys', authenticate, async (req, res, next) => {
  try {
    const keys = await getPublicAppKeys();
    res.json(keys);
  } catch (e) { next(e); }
});

// Admin sets a credential value
router.post('/', authenticateAdmin, async (req, res, next) => {
  try {
    const { key_name, value } = req.body;
    if (!key_name || !value) return res.status(400).json({ message: 'key_name and value required' });
    await setCredential(key_name, value);
    res.json({ message: 'Credential saved' });
  } catch (e) { next(e); }
});

module.exports = router;
