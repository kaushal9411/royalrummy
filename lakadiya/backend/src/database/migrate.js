require('dotenv').config();
const fs = require('fs');
const path = require('path');
const { pool } = require('../config/database');

const MIGRATIONS_DIR = path.join(__dirname, '../../../database/migrations');

async function migrate() {
  const client = await pool.connect();
  try {
    await client.query(`
      CREATE TABLE IF NOT EXISTS migrations (
        id         SERIAL PRIMARY KEY,
        filename   VARCHAR(255) UNIQUE NOT NULL,
        ran_at     TIMESTAMPTZ DEFAULT NOW()
      )
    `);

    const { rows: ran } = await client.query('SELECT filename FROM migrations');
    const ranSet = new Set(ran.map((r) => r.filename));

    const files = fs.readdirSync(MIGRATIONS_DIR)
      .filter((f) => f.endsWith('.sql'))
      .sort();

    for (const file of files) {
      if (ranSet.has(file)) {
        console.log(`[skip] ${file}`);
        continue;
      }
      const sql = fs.readFileSync(path.join(MIGRATIONS_DIR, file), 'utf8');
      await client.query('BEGIN');
      await client.query(sql);
      await client.query('INSERT INTO migrations (filename) VALUES ($1)', [file]);
      await client.query('COMMIT');
      console.log(`[done] ${file}`);
    }
    console.log('All migrations complete.');
  } catch (err) {
    await client.query('ROLLBACK');
    console.error('Migration failed:', err.message);
    process.exit(1);
  } finally {
    client.release();
    await pool.end();
  }
}

migrate();
