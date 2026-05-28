require('dotenv').config();
const { Pool } = require('pg');

const pool = new Pool({
  host: process.env.DB_HOST,
  port: parseInt(process.env.DB_PORT),
  database: process.env.DB_NAME,
  user: process.env.DB_USER,
  password: process.env.DB_PASSWORD,
});

async function addPendingRequests() {
  const client = await pool.connect();
  try {
    console.log('Adding pending friend requests FOR deeksha01...\n');

    const deekshaRes = await client.query('SELECT id FROM users WHERE username = $1', ['deeksha01']);
    const deekshaId = deekshaRes.rows[0].id;

    const requesters = [
      'ProPlayer100',
      'ChampionAce',
      'LuckyStrike',
    ];

    for (const requester of requesters) {
      const requesterRes = await client.query(
        'SELECT id FROM users WHERE username = $1',
        [requester]
      );
      if (!requesterRes.rows.length) continue;

      const requesterId = requesterRes.rows[0].id;

      // Check if already exists
      const existRes = await client.query(
        'SELECT id FROM friendships WHERE user_id = $1 AND friend_id = $2',
        [requesterId, deekshaId]
      );

      if (existRes.rows.length) {
        // Update to pending
        await client.query(
          'UPDATE friendships SET status = $1 WHERE user_id = $2 AND friend_id = $3',
          ['pending', requesterId, deekshaId]
        );
      } else {
        await client.query(
          'INSERT INTO friendships (user_id, friend_id, status) VALUES ($1, $2, $3)',
          [requesterId, deekshaId, 'pending']
        );
      }

      console.log(`✅ Created pending request: ${requester} -> deeksha01`);
    }

    console.log('\n✨ Done!\n');

  } catch (err) {
    console.error('Error:', err.message);
  } finally {
    client.release();
    await pool.end();
  }
}

addPendingRequests();
