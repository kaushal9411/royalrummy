require('dotenv').config();
const { Pool } = require('pg');

const pool = new Pool({
  host:     process.env.DB_HOST     || 'localhost',
  port:     parseInt(process.env.DB_PORT || '5432'),
  database: process.env.DB_NAME     || 'lakadiya',
  user:     process.env.DB_USER     || 'postgres',
  password: process.env.DB_PASSWORD || 'postgres',
});

async function seedDummyFriends() {
  const client = await pool.connect();
  try {
    console.log('🌱 Seeding dummy friends and requests...\n');

    // Get main user (7007249428)
    const mainUserRes = await client.query(
      'SELECT id, username FROM users WHERE mobile = $1',
      ['7007249428']
    );

    if (!mainUserRes.rows.length) {
      console.log('❌ Main user (7007249428) not found!');
      return;
    }

    const mainUserId = mainUserRes.rows[0].id;
    console.log(`✅ Found main user: ${mainUserRes.rows[0].username} (${mainUserId})\n`);

    // Get or create dummy users
    const dummyUsers = [
      { mobile: '9000000001', username: 'AceKing2024', status: 'accepted' },
      { mobile: '9000000002', username: 'SharpShark99', status: 'pending' },
      { mobile: '9000000003', username: 'WildDealer007', status: 'accepted' },
      { mobile: '9000000005', username: 'RoyalMaster88', status: 'accepted' },
    ];

    for (const dummy of dummyUsers) {
      const userRes = await client.query(
        'SELECT id FROM users WHERE mobile = $1',
        [dummy.mobile]
      );

      if (!userRes.rows.length) {
        console.log(`⚠️  Dummy user ${dummy.username} not found, creating...`);
        const insertRes = await client.query(
          `INSERT INTO users (username, mobile, provider, coins, xp, level)
           VALUES ($1, $2, 'local', 1000, 2000, 5)
           RETURNING id`,
          [dummy.username, dummy.mobile]
        );
        dummy.userId = insertRes.rows[0].id;
      } else {
        dummy.userId = userRes.rows[0].id;
      }

      console.log(`✅ User: ${dummy.username} (${dummy.userId})`);
    }

    console.log('\n🔗 Creating friendships...\n');

    for (const dummy of dummyUsers) {
      // Check if friendship already exists
      const existingRes = await client.query(
        'SELECT id FROM friendships WHERE user_id = $1 AND friend_id = $2',
        [mainUserId, dummy.userId]
      );

      if (existingRes.rows.length) {
        console.log(`⏭️  Friendship already exists: ${dummy.username}`);
        continue;
      }

      if (dummy.status === 'accepted') {
        // Create bidirectional friendship
        await client.query(
          'INSERT INTO friendships (user_id, friend_id, status) VALUES ($1, $2, $3)',
          [mainUserId, dummy.userId, 'accepted']
        );
        await client.query(
          'INSERT INTO friendships (user_id, friend_id, status) VALUES ($1, $2, $3)',
          [dummy.userId, mainUserId, 'accepted']
        );
        console.log(`✅ ACCEPTED friendship: ${dummy.username}`);
      } else if (dummy.status === 'pending') {
        // Create pending request (from dummy to main user)
        await client.query(
          'INSERT INTO friendships (user_id, friend_id, status) VALUES ($1, $2, $3)',
          [dummy.userId, mainUserId, 'pending']
        );
        console.log(`📬 PENDING request FROM: ${dummy.username}`);
      }
    }

    console.log('\n✨ Friend requests seeding complete!\n');
    console.log('📊 Summary:');
    console.log('   - 3 Accepted Friends: AceKing2024, WildDealer007, RoyalMaster88');
    console.log('   - 1 Pending Request: SharpShark99 (sent to you)\n');

  } catch (err) {
    console.error('❌ Error:', err.message);
  } finally {
    client.release();
    await pool.end();
  }
}

seedDummyFriends();
