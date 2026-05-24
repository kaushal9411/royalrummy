const crypto = require('crypto');

/**
 * Generate a unique referral code: 8 alphanumeric chars, uppercase
 */
function generateReferralCode(username = '') {
  const prefix = username.substring(0, 2).toUpperCase().padEnd(2, 'X');
  const random = crypto.randomBytes(3).toString('hex').toUpperCase();
  return `${prefix}${random}`;
}

/**
 * Generate a 6-digit numeric OTP
 */
function generateOtp() {
  return String(Math.floor(100000 + Math.random() * 900000));
}

/**
 * Generate a short private table code (e.g. "TBL-AB3X")
 */
function generateTableCode() {
  return `TBL-${crypto.randomBytes(3).toString('hex').toUpperCase()}`;
}

/**
 * Generate a ticket number for support (e.g. "TKT-20240115-0001")
 */
function generateTicketNumber() {
  const date = new Date().toISOString().slice(0, 10).replace(/-/g, '');
  const random = crypto.randomBytes(2).toString('hex').toUpperCase();
  return `TKT-${date}-${random}`;
}

/**
 * Mask a phone number for display: "+919876543210" → "+91*****3210"
 */
function maskPhone(phone) {
  if (!phone || phone.length < 6) return phone;
  return phone.slice(0, 3) + '*'.repeat(phone.length - 7) + phone.slice(-4);
}

/**
 * Mask an email for display: "user@example.com" → "u***@example.com"
 */
function maskEmail(email) {
  if (!email || !email.includes('@')) return email;
  const [local, domain] = email.split('@');
  return `${local[0]}${'*'.repeat(Math.max(local.length - 1, 2))}@${domain}`;
}

/**
 * Calculate platform rake (capped per config)
 */
function calculateRake(prizePool, rakePercent = 0.10, maxRake = null) {
  const rake = prizePool * rakePercent;
  return maxRake ? Math.min(rake, maxRake) : rake;
}

/**
 * Paginate a query: returns { offset, limit } from page/limit params
 */
function paginationParams(page = 1, limit = 20) {
  const p = Math.max(1, parseInt(page));
  const l = Math.min(100, Math.max(1, parseInt(limit)));
  return { offset: (p - 1) * l, limit: l, page: p };
}

/**
 * Sleep for ms milliseconds (for bots, timers, etc.)
 */
function sleep(ms) {
  return new Promise(resolve => setTimeout(resolve, ms));
}

/**
 * Shuffle array using Fisher-Yates with crypto seed
 */
function shuffleArray(arr) {
  const shuffled = [...arr];
  for (let i = shuffled.length - 1; i > 0; i--) {
    const j = crypto.randomInt(i + 1);
    [shuffled[i], shuffled[j]] = [shuffled[j], shuffled[i]];
  }
  return shuffled;
}

module.exports = {
  generateReferralCode,
  generateOtp,
  generateTableCode,
  generateTicketNumber,
  maskPhone,
  maskEmail,
  calculateRake,
  paginationParams,
  sleep,
  shuffleArray,
};
