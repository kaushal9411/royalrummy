#!/usr/bin/env node
/**
 * Database Cleanup Script
 * Removes all data from tables EXCEPT admin account
 * WARNING: This will permanently DELETE all non-admin user data!
 */

require('dotenv').config();
const { Pool } = require('pg');

const pool = new Pool({
  host: process.env.DB_HOST || 'localhost',
  port: parseInt(process.env.DB_PORT || '5432'),
  database: process.env.DB_NAME || 'lakadiya',
  user: process.env.DB_USER || 'postgres',
  password: process.env.DB_PASSWORD || 'postgres',
});

async function cleanupDatabase() {
  const client = await pool.connect();
  
  try {
    console.log('🗑️  Starting database cleanup...\n');
    
    // Get admin users first
    const adminResult = await client.query(
      'SELECT id, username, email FROM users WHERE is_admin = TRUE'
    );
    
    if (adminResult.rows.length === 0) {
      console.error('❌ ERROR: No admin account found in database!');
      console.error('   Please create an admin account first before cleanup.');
      process.exit(1);
    }
    
    console.log('✅ Found admin accounts:');
    adminResult.rows.forEach(admin => {
      console.log(`   - ${admin.username} (${admin.email})`);
    });
    console.log('');
    
    const adminIds = adminResult.rows.map(a => a.id);
    
    // Create admin ID list for SQL IN clause
    const adminIdList = adminIds.map(id => `'${id}'`).join(',');
    
    // Start transaction
    await client.query('BEGIN');
    
    console.log('🔄 Deleting game data...');
    
    // 1. Delete trick_cards
    await client.query(`
      DELETE FROM trick_cards WHERE trick_id IN (
        SELECT id FROM tricks WHERE round_id IN (
          SELECT id FROM rounds WHERE match_id IN (
            SELECT id FROM matches WHERE room_id IN (
              SELECT id FROM rooms WHERE host_id NOT IN (${adminIdList})
            )
          )
        )
      )
    `);
    
    // 2. Delete tricks
    await client.query(`
      DELETE FROM tricks WHERE round_id IN (
        SELECT id FROM rounds WHERE match_id IN (
          SELECT id FROM matches WHERE room_id IN (
            SELECT id FROM rooms WHERE host_id NOT IN (${adminIdList})
          )
        )
      )
    `);
    
    // 3. Delete bids
    await client.query(`
      DELETE FROM bids WHERE round_id IN (
        SELECT id FROM rounds WHERE match_id IN (
          SELECT id FROM matches WHERE room_id IN (
            SELECT id FROM rooms WHERE host_id NOT IN (${adminIdList})
          )
        )
      )
    `);
    
    // 4. Delete rounds
    await client.query(`
      DELETE FROM rounds WHERE match_id IN (
        SELECT id FROM matches WHERE room_id IN (
          SELECT id FROM rooms WHERE host_id NOT IN (${adminIdList})
        )
      )
    `);
    
    // 5. Delete match_players
    await client.query(`
      DELETE FROM match_players WHERE match_id IN (
        SELECT id FROM matches WHERE room_id IN (
          SELECT id FROM rooms WHERE host_id NOT IN (${adminIdList})
        )
      )
    `);
    
    // 6. Delete matches
    await client.query(`
      DELETE FROM matches WHERE room_id IN (
        SELECT id FROM rooms WHERE host_id NOT IN (${adminIdList})
      )
    `);
    
    // 7. Delete room_players
    await client.query(`
      DELETE FROM room_players WHERE room_id IN (
        SELECT id FROM rooms WHERE host_id NOT IN (${adminIdList})
      )
    `);
    
    // 8. Delete rooms
    await client.query(`
      DELETE FROM rooms WHERE host_id NOT IN (${adminIdList})
    `);
    
    console.log('✅ Game data deleted');
    
    console.log('🔄 Deleting user-related data...');
    
    // 9. Delete notifications
    await client.query(`
      DELETE FROM notifications WHERE user_id NOT IN (${adminIdList})
    `);
    
    // 10. Delete payment transactions
    await client.query(`
      DELETE FROM payment_transactions WHERE user_id NOT IN (${adminIdList})
    `);
    
    // 11. Delete wallet balance
    await client.query(`
      DELETE FROM wallet_balance WHERE user_id NOT IN (${adminIdList})
    `);
    
    // 12. Delete friendships
    await client.query(`
      DELETE FROM friendships WHERE user_id NOT IN (${adminIdList})
      OR friend_id NOT IN (${adminIdList})
    `);
    
    // 13. Delete coin transactions
    await client.query(`
      DELETE FROM coin_transactions WHERE user_id NOT IN (${adminIdList})
    `);
    
    // 14. Delete player stats
    await client.query(`
      DELETE FROM player_stats WHERE user_id NOT IN (${adminIdList})
    `);
    
    console.log('✅ User-related data deleted');
    
    console.log('🔄 Deleting non-admin users...');
    
    // 15. Delete non-admin users
    const deleteUserResult = await client.query(
      'DELETE FROM users WHERE is_admin = FALSE RETURNING id, username'
    );
    
    console.log(`✅ Deleted ${deleteUserResult.rows.length} non-admin users`);
    
    // Commit transaction
    await client.query('COMMIT');
    
    console.log('\n📊 Verification - Remaining data:');
    
    // Verify remaining data
    const userCount = await client.query('SELECT COUNT(*) FROM users');
    const roomCount = await client.query('SELECT COUNT(*) FROM rooms');
    const matchCount = await client.query('SELECT COUNT(*) FROM matches');
    const friendshipCount = await client.query('SELECT COUNT(*) FROM friendships');
    const notificationCount = await client.query('SELECT COUNT(*) FROM notifications');
    const paymentCount = await client.query('SELECT COUNT(*) FROM payment_transactions');
    const coinTxCount = await client.query('SELECT COUNT(*) FROM coin_transactions');
    
    console.log(`   Users: ${userCount.rows[0].count}`);
    console.log(`   Rooms: ${roomCount.rows[0].count}`);
    console.log(`   Matches: ${matchCount.rows[0].count}`);
    console.log(`   Friendships: ${friendshipCount.rows[0].count}`);
    console.log(`   Notifications: ${notificationCount.rows[0].count}`);
    console.log(`   Payment Transactions: ${paymentCount.rows[0].count}`);
    console.log(`   Coin Transactions: ${coinTxCount.rows[0].count}`);
    
    const remainingUsers = await client.query(
      'SELECT id, username, email, is_admin FROM users'
    );
    console.log('\n👤 Remaining users:');
    remainingUsers.rows.forEach(user => {
      console.log(`   - ${user.username} (${user.email}) ${user.is_admin ? '[ADMIN]' : ''}`);
    });
    
    console.log('\n✨ Database cleanup completed successfully!');
    console.log('🔒 All non-admin user data has been removed.');
    
  } catch (err) {
    console.error('❌ ERROR during cleanup:', err.message);
    await client.query('ROLLBACK').catch(() => {});
    process.exit(1);
  } finally {
    client.release();
    await pool.end();
  }
}

// Confirm before running
console.log('\n⚠️  WARNING: This will permanently DELETE all non-admin user data!');
console.log('   This includes: users, rooms, matches, messages, transactions, etc.\n');

const answer = require('readline').createInterface({
  input: process.stdin,
  output: process.stdout
});

answer.question('Type "DELETE ALL" to confirm cleanup: ', async (input) => {
  answer.close();
  
  if (input === 'DELETE ALL') {
    await cleanupDatabase();
  } else {
    console.log('❌ Cleanup cancelled.');
    process.exit(0);
  }
});
