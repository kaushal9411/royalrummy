const router = require('express').Router();
const { authenticate } = require('../../middleware/auth.middleware');
const service = require('./leaderboard.service');

router.get('/', async (req, res, next) => {
  try {
    const { type = 'wins', limit = 50 } = req.query;
    const data = await service.getLeaderboard(type, Math.min(Number(limit), 100));
    res.json(data);
  } catch (err) { next(err); }
});

router.get('/my-rank', authenticate, async (req, res, next) => {
  try {
    const rank = await service.getUserRank(req.user.id);
    res.json({ rank });
  } catch (err) { next(err); }
});

module.exports = router;
