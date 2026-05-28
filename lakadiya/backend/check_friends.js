require('dotenv').config();
const { Pool } = require('pg');

const pool = new Pool({
  host: process.env.DB_HOST,
  port: parseInt(process.env.DB_PORT),
  database: process.env.DB_NAME,
  user: process.env.DB_USER,
  password: process.env.DB_PASSWORD,
});

(async () => {
  const client = await pool.connect();
  
  // Get main user
  const mainRes = await client.query('SELECT id FROM users WHERE mobile = $1', ['7007249428']);
  if (!mainRes.rows.length) {
    console.log('Main user not found');
    client.release();
    await pool.end();
    return;
  }
  
  const mainId = mainRes.rows[0].id;
  
  // Check friendships
  const res = await client.query(`
    SELECT f.*, u1.username as from_user, u2.username as to_user, f.status
    FROM friendships f
    JOIN users u1 ON u1.id = f.user_id
    JOIN users u2 ON u2.id = f.friend_id
    WHERE u1.id = $1 OR u2.id = $1
    ORDER BY f.created_at DESC
  `, [mainId]);
  
  console.log('Current Friendships:');
  console.log('='.repeat(60));
  res.rows.forEach(row => {
    console.log(`${row.from_user} -> ${row.to_user} [${row.status}]`);
  });
  console.log('='.repeat(60));
  console.log(`Total: ${res.rows.length} records\n`);
  
  client.release();
  await pool.end();
})().catch(err => console.error(err));
