// Run on the server by 03-deploy-app.sh — generates fresh secrets for this
// test deploy's backend/.env. Never reuse these for anything beyond
// testing; they're only ever written to the instance's own .env.
const crypto = require('node:crypto');

console.log(`JWT_SECRET=${crypto.randomBytes(48).toString('base64')}`);
console.log(`ADMIN_SECRET=${crypto.randomBytes(24).toString('hex')}`);
// Must be exactly 32 chars — AES-256 key for the credentials table (see
// backend/.env.example).
console.log(`CREDENTIALS_ENCRYPTION_KEY=${crypto.randomBytes(16).toString('hex')}`);
console.log(`DB_PASSWORD=${crypto.randomBytes(18).toString('base64url')}`);
