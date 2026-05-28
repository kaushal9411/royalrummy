require('dotenv').config();
const { Pool } = require('pg');

const pool = new Pool({
  host: process.env.DB_HOST,
  port: parseInt(process.env.DB_PORT),
  database: process.env.DB_NAME,
  user: process.env.DB_USER,
  password: process.env.DB_PASSWORD,
});

async function seedDeeksha() {
  const client = await pool.connect();
  try {
    console.log('🌱 Seeding dummy friends and requests for deeksha01...\n');

    // Get deeksha01 user
    const userRes = await client.query('SELECT id FROM users WHERE username = $1', ['deeksha01']);
    if (!userRes.rows.length) {
      console.log('❌ User deeksha01 not found');
      return;
    }
    const deekshaId = userRes.rows[0].id;

    // Create or get 4 dummy friends
    const dummyUsers = [
      { username: 'ProPlayer100', mobile: '9001234567', status: 'accepted' },
      { username: 'ChampionAce', mobile: '9002345678', status: 'accepted' },
      { username: 'LuckyStrike', mobile: '9003456789', status: 'accepted' },
      { username: 'DareDevil99', mobile: '9004567890', status: 'pending' }, // Request from this user
    ];

    const userIds = {};

    for (const dummy of dummyUsers) {
      let userId;
      const existRes = await client.query(
        'SELECT id FROM users WHERE username = $1',
        [dummy.username]
      );

      if (existRes.rows.length) {
        userId = existRes.rows[0].id;
      } else {
        const insertRes = await client.query(
          `INSERT INTO users (username, mobile, provider, coins, xp, level)
           VALUES ($1, $2, 'local', 1500, 3500, 8)
           RETURNING id`,
          [dummy.username, dummy.mobile]
        );
        userId = insertRes.rows[0].id;
        console.log(`✅ Created user: ${dummy.username}`);
      }

      userIds[dummy.username] = { userId, status: dummy.status };
    }

    console.log('\n🔗 Creating friendships...\n');

    for (const dummy of dummyUsers) {
      const { userId, status } = userIds[dummy.username];

      // Check if already exists
      const existRes = await client.query(
        'SELECT id FROM friendships WHERE user_id = $1 AND friend_id = $2',
        [status === 'accepted' ? deekshaId : userId, status === 'accepted' ? userId : deekshaId]
      );

      if (existRes.rows.length) {
        console.log(`⏭️  Already exists: ${dummy.username}`);
        continue;
      }

      if (status === 'accepted') {
        // Bidirectional friendship
        await client.query(
          'INSERT INTO friendships (user_id, friend_id, status) VALUES ($1, $2, $3)',
          [deekshaId, userId, 'accepted']
        );
        await client.query(
          'INSERT INTO friendships (user_id, friend_id, status) VALUES ($1, $2, $3)',
          [userId, deekshaId, 'accepted']
        );
        console.log(`✅ ACCEPTED: ${dummy.username} <-> deeksha01`);
      } else if (status === 'pending') {
        // Pending: from dummy user to deeksha01
        await client.query(
          'INSERT INTO friendships (user_id, friend_id, status) VALUES ($1, $2, $3)',
          [userId, deekshaId, 'pending']
        );
        console.log(`📬 PENDING: ${dummy.username} -> deeksha01`);
      }
    }

    console.log('\n✨ Seeding complete!\n');
    console.log('📊 Summary for deeksha01:');
    console.log('   - 3 Accepted Friends');
    console.log('   - 1 Pending Request\n');

  } catch (err) {
    console.error('❌ Error:', err.message);
  } finally {
    client.release();
    await pool.end();
  }
}

seedDeeksha();
