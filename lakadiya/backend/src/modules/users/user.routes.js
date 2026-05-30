const router = require('express').Router();
const { authenticate } = require('../../middleware/auth.middleware');
const controller = require('./user.controller');
const { isExcluded, checkSpendLimit } = require('../responsible_gaming/responsible_gaming.service');
const { query } = require('../../config/database');

router.use(authenticate);

router.get('/search',    controller.searchUsers);
router.get('/me', controller.getMe);
router.patch('/me', controller.updateProfile);
router.get('/me/matches', controller.getMatchHistory);
router.get('/me/friends', controller.getFriends);
router.get('/me/friend-requests', controller.getPendingRequests);
router.post('/friends/:userId', controller.sendFriendRequest);
router.post('/friends/:userId/accept', controller.acceptFriendRequest);
router.post('/friends/:userId/decline', controller.declineFriendRequest);
router.get('/notifications', controller.getNotifications);
router.patch('/notifications/read', controller.markNotificationsRead);

// ── Compliance status — used by mobile lobby to show warnings ─────────────────
router.get('/me/compliance', authenticate, async (req, res, next) => {
  try {
    const userId = req.user.id;

    // Fetch user compliance fields + KYC status in parallel
    const [userRow, kycRow, rgRow] = await Promise.all([
      query(
        'SELECT date_of_birth, is_minor, kyc_verified FROM users WHERE id=$1',
        [userId]
      ),
      query(
        "SELECT status FROM kyc_submissions WHERE user_id=$1",
        [userId]
      ),
      query(
        'SELECT self_excluded, exclusion_until FROM responsible_gaming_settings WHERE user_id=$1',
        [userId]
      ),
    ]);

    const user = userRow.rows[0] || {};
    const kycStatus = kycRow.rows[0]?.status || 'not_submitted';

    // Compute age
    let age = null;
    if (user.date_of_birth) {
      const birth = new Date(user.date_of_birth);
      const now   = new Date();
      age = now.getFullYear() - birth.getFullYear();
      if (now.getMonth() < birth.getMonth() ||
         (now.getMonth() === birth.getMonth() && now.getDate() < birth.getDate())) age--;
    }

    // Self exclusion (auto-expire handled in service, replicate here)
    let selfExcluded = false;
    let exclusionUntil = null;
    if (rgRow.rows.length && rgRow.rows[0].self_excluded) {
      const until = rgRow.rows[0].exclusion_until;
      if (!until || new Date(until) > new Date()) {
        selfExcluded = true;
        exclusionUntil = until;
      }
    }

    // Spend limits
    const [daily, weekly, monthly] = await Promise.all([
      checkSpendLimit(userId, 'daily'),
      checkSpendLimit(userId, 'weekly'),
      checkSpendLimit(userId, 'monthly'),
    ]);

    const canPlayPaid = !selfExcluded && !user.is_minor &&
                        !daily.exceeded && !weekly.exceeded && !monthly.exceeded;

    let restrictionReason = null;
    if (user.is_minor)        restrictionReason = 'Under 18 — real-money games restricted';
    else if (selfExcluded)    restrictionReason = 'Self-excluded from real-money games';
    else if (daily.exceeded)  restrictionReason = `Daily limit reached (₹${Number(daily.used).toFixed(0)} / ₹${Number(daily.limit).toFixed(0)})`;
    else if (weekly.exceeded) restrictionReason = `Weekly limit reached (₹${Number(weekly.used).toFixed(0)} / ₹${Number(weekly.limit).toFixed(0)})`;
    else if (monthly.exceeded)restrictionReason = `Monthly limit reached (₹${Number(monthly.used).toFixed(0)} / ₹${Number(monthly.limit).toFixed(0)})`;

    res.json({
      age_verified:   !!user.date_of_birth,
      is_minor:       !!user.is_minor,
      age,
      kyc_status:     kycStatus,
      self_excluded:  selfExcluded,
      exclusion_until: exclusionUntil,
      daily_limit:    { ...daily  },
      weekly_limit:   { ...weekly },
      monthly_limit:  { ...monthly },
      can_play_paid:  canPlayPaid,
      restriction_reason: restrictionReason,
    });
  } catch (e) { next(e); }
});

module.exports = router;
