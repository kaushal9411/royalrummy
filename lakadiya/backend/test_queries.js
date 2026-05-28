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
    // Get deeksha01
    const userRes = await client.query('SELECT id, username FROM users WHERE username = $1', ['deeksha01']);
    const deeksha = userRes.rows[0];
    
    console.log('🔍 Testing deeksha01 (deeksha01):\n');
    
    // Test getFriends query
    const friendsRes = await client.query(`
      SELECT u.id, u.username, u.avatar_url, u.level, u.last_seen, f.status
      FROM friendships f
      JOIN users u ON u.id = f.friend_id
      WHERE f.user_id = $1 AND f.status = 'accepted'
      ORDER BY u.username
    `, [deeksha.id]);
    
    console.log('Friends (status=accepted):');
    console.log(JSON.stringify(friendsRes.rows, null, 2));
    
    // Test getPendingRequests query
    const pendingRes = await client.query(`
      SELECT f.id, f.user_id as from_user_id, u.username as from_user_name, u.avatar_url as from_user_avatar, u.level, f.created_at
      FROM friendships f
      JOIN users u ON u.id = f.user_id
      WHERE f.friend_id = $1 AND f.status = 'pending'
      ORDER BY f.created_at DESC
    `, [deeksha.id]);
    
    console.log('\n\nPending Requests (friend_id=deeksha, status=pending):');
    console.log(JSON.stringify(pendingRes.rows, null, 2));
    
  } catch (err) {
    console.error('Error:', err.message);
  } finally {
    client.release();
    await pool.end();
  }
})();
