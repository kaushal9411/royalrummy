const express = require('express');
const { authenticate } = require('../../middleware/auth.middleware');
const rg = require('./responsible_gaming.service');

const router = express.Router();

router.get('/settings', authenticate, async (req, res, next) => {
  try { res.json(await rg.getSettings(req.user.id)); }
  catch (e) { next(e); }
});

router.put('/settings', authenticate, async (req, res, next) => {
  try {
    const { daily_limit, weekly_limit, monthly_limit } = req.body;
    res.json(await rg.updateSettings(req.user.id, {
      dailyLimit: daily_limit, weeklyLimit: weekly_limit, monthlyLimit: monthly_limit,
    }));
  } catch (e) { next(e); }
});

router.post('/self-exclude', authenticate, async (req, res, next) => {
  try {
    const { days } = req.body;
    if (!days || days < 1) return res.status(400).json({ message: 'days must be >= 1' });
    res.json(await rg.setSelfExclusion(req.user.id, Number(days)));
  } catch (e) { next(e); }
});

router.delete('/self-exclude', authenticate, async (req, res, next) => {
  try {
    res.json(await rg.setSelfExclusion(req.user.id, 0));
  } catch (e) { next(e); }
});

module.exports = router;
