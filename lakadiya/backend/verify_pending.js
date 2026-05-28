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
  
  try {
    const userRes = await client.query('SELECT id FROM users WHERE username = $1', ['deeksha01']);
    const deekshaId = userRes.rows[0].id;
    
    // Check all friendships for deeksha01
    const allRes = await client.query(`
      SELECT f.*, u1.username as from_user, u2.username as to_user
      FROM friendships f
      JOIN users u1 ON u1.id = f.user_id
      JOIN users u2 ON u2.id = f.friend_id
      WHERE f.user_id = $1 OR f.friend_id = $1
      ORDER BY f.created_at DESC
    `, [deekshaId]);
    
    console.log('All friendships involving deeksha01:');
    allRes.rows.forEach(row => {
      console.log(`  ${row.from_user} -> ${row.to_user} [${row.status}]`);
    });
    
    // Now check pending WHERE friend_id = deeksha01
    const pendingRes = await client.query(`
      SELECT f.id, f.user_id as from_user_id, u.username as from_user_name, u.avatar_url, u.level
      FROM friendships f
      JOIN users u ON u.id = f.user_id
      WHERE f.friend_id = $1 AND f.status = 'pending'
    `, [deekshaId]);
    
    console.log('\nPending requests TO deeksha01:');
    console.log(JSON.stringify(pendingRes.rows, null, 2));
    
  } catch (err) {
    console.error('Error:', err);
  } finally {
    client.release();
    await pool.end();
  }
})();
