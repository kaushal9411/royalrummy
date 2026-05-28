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
    // Get deeksha01 user
    const userRes = await client.query('SELECT id, username, mobile FROM users WHERE username = $1', ['deeksha01']);
    if (!userRes.rows.length) {
      console.log('❌ User deeksha01 not found');
      client.release();
      await pool.end();
      return;
    }
    
    const deeksha = userRes.rows[0];
    console.log('✅ Found deeksha01:', deeksha);
    
    // Get friends for deeksha01
    const friendsRes = await client.query(`
      SELECT f.*, u.username, u.mobile, u.level
      FROM friendships f
      JOIN users u ON u.id = f.friend_id
      WHERE f.user_id = $1 AND f.status = 'accepted'
    `, [deeksha.id]);
    
    console.log('\nFriends of deeksha01:');
    friendsRes.rows.forEach(row => {
      console.log(`  - ${row.username} (${row.mobile})`);
    });
    
    // Get pending requests for deeksha01
    const pendingRes = await client.query(`
      SELECT f.*, u.username, u.mobile, u.level
      FROM friendships f
      JOIN users u ON u.id = f.user_id
      WHERE f.friend_id = $1 AND f.status = 'pending'
    `, [deeksha.id]);
    
    console.log('\nPending requests TO deeksha01:');
    pendingRes.rows.forEach(row => {
      console.log(`  - ${row.username} (${row.mobile})`);
    });
    
    // Check if friendships table has correct schema
    const schemaRes = await client.query(`
      SELECT column_name, data_type, is_nullable
      FROM information_schema.columns
      WHERE table_name = 'friendships'
      ORDER BY ordinal_position
    `);
    
    console.log('\nFriendships table schema:');
    schemaRes.rows.forEach(row => {
      console.log(`  ${row.column_name}: ${row.data_type} (nullable: ${row.is_nullable})`);
    });
    
  } catch (err) {
    console.error('Error:', err.message);
  } finally {
    client.release();
    await pool.end();
  }
})();
