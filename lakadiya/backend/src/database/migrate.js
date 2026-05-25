require('dotenv').config();
const fs   = require('fs');
const path = require('path');
const { Client, Pool } = require('pg');

const MIGRATIONS_DIR = path.join(__dirname, '../../../database/migrations');

const dbName = process.env.DB_NAME || 'lakadiya';

const baseConfig = {
  host:     process.env.DB_HOST     || 'localhost',
  port:     parseInt(process.env.DB_PORT || '5432'),
  user:     process.env.DB_USER     || 'postgres',
  password: process.env.DB_PASSWORD || 'postgres',
};

async function ensureDatabase() {
  // Connect to the default 'postgres' database to check/create our db
  const adminClient = new Client({ ...baseConfig, database: 'postgres' });
  await adminClient.connect();
  try {
    const res = await adminClient.query(
      `SELECT 1 FROM pg_database WHERE datname = $1`, [dbName]
    );
    if (res.rowCount === 0) {
      await adminClient.query(`CREATE DATABASE "${dbName}"`);
      console.log(`[init] Database "${dbName}" created.`);
    } else {
      console.log(`[init] Database "${dbName}" already exists.`);
    }
  } finally {
    await adminClient.end();
  }
}

async function migrate() {
  await ensureDatabase();

  const pool = new Pool({ ...baseConfig, database: dbName, max: 5 });
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
    await client.query('ROLLBACK').catch(() => {});
    console.error('Migration failed:', err.message);
    process.exit(1);
  } finally {
    client.release();
    await pool.end();
  }
}

migrate();
