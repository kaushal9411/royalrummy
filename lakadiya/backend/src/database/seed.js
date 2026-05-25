require('dotenv').config();
const bcrypt = require('bcryptjs');
const { Pool } = require('pg');

const pool = new Pool({
  host:     process.env.DB_HOST     || 'localhost',
  port:     parseInt(process.env.DB_PORT || '5432'),
  database: process.env.DB_NAME     || 'lakadiya',
  user:     process.env.DB_USER     || 'postgres',
  password: process.env.DB_PASSWORD || 'postgres',
});

async function seed() {
  const client = await pool.connect();
  try {
    const email    = 'admin@lakadiya.com';
    const password = 'Admin@123';
    const hash     = await bcrypt.hash(password, 12);

    const existing = await client.query(
      'SELECT id FROM users WHERE email = $1', [email]
    );

    if (existing.rows.length) {
      // Make sure existing user is admin
      await client.query(
        'UPDATE users SET is_admin = TRUE, password_hash = $1 WHERE email = $2',
        [hash, email]
      );
      console.log('Admin user updated.');
    } else {
      const result = await client.query(
        `INSERT INTO users (username, email, password_hash, provider, is_admin)
         VALUES ('Admin', $1, $2, 'local', TRUE)
         RETURNING id`,
        [email, hash]
      );
      await client.query(
        'INSERT INTO player_stats (user_id) VALUES ($1)',
        [result.rows[0].id]
      );
      console.log('Admin user created.');
    }

    console.log('');
    console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    console.log('  Admin Login Credentials');
    console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
    console.log(`  Email    : ${email}`);
    console.log(`  Password : ${password}`);
    console.log(`  URL      : http://localhost:3000/login`);
    console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  } finally {
    client.release();
    await pool.end();
  }
}

seed().catch((err) => { console.error(err.message); process.exit(1); });
