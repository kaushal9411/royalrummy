-- ============================================================================
-- LAKADIYA DATABASE CLEANUP SCRIPT
-- Removes all data from tables EXCEPT the admin account
-- ============================================================================
-- WARNING: This script will DELETE all non-admin user data permanently!
-- ============================================================================

-- First, get the admin user ID (assuming admin is identified by is_admin = TRUE)
-- Store it in a variable so we can preserve it

BEGIN;

-- Identify admin user IDs (should be just one or a few)
-- We'll preserve users where is_admin = TRUE

-- Step 1: Delete all game-related data (this cascades through foreign keys)
DELETE FROM tricks WHERE round_id IN (
  SELECT id FROM rounds WHERE match_id IN (
    SELECT id FROM matches WHERE room_id IN (
      SELECT id FROM rooms WHERE host_id NOT IN (
        SELECT id FROM users WHERE is_admin = TRUE
      )
    )
  )
);

DELETE FROM trick_cards;

DELETE FROM bids WHERE round_id IN (
  SELECT id FROM rounds WHERE match_id IN (
    SELECT id FROM matches WHERE room_id IN (
      SELECT id FROM rooms WHERE host_id NOT IN (
        SELECT id FROM users WHERE is_admin = TRUE
      )
    )
  )
);

DELETE FROM rounds WHERE match_id IN (
  SELECT id FROM matches WHERE room_id IN (
    SELECT id FROM rooms WHERE host_id NOT IN (
      SELECT id FROM users WHERE is_admin = TRUE
    )
  )
);

DELETE FROM match_players WHERE match_id IN (
  SELECT id FROM matches WHERE room_id IN (
    SELECT id FROM rooms WHERE host_id NOT IN (
      SELECT id FROM users WHERE is_admin = TRUE
    )
  )
);

DELETE FROM matches WHERE room_id IN (
  SELECT id FROM rooms WHERE host_id NOT IN (
    SELECT id FROM users WHERE is_admin = TRUE
  )
);

DELETE FROM room_players WHERE room_id IN (
  SELECT id FROM rooms WHERE host_id NOT IN (
    SELECT id FROM users WHERE is_admin = TRUE
  )
);

DELETE FROM rooms WHERE host_id NOT IN (
  SELECT id FROM users WHERE is_admin = TRUE
);

-- Step 2: Delete notifications for non-admin users
DELETE FROM notifications WHERE user_id NOT IN (
  SELECT id FROM users WHERE is_admin = TRUE
);

-- Step 3: Delete payment transactions for non-admin users
DELETE FROM payment_transactions WHERE user_id NOT IN (
  SELECT id FROM users WHERE is_admin = TRUE
);

-- Step 4: Delete wallet balance for non-admin users
DELETE FROM wallet_balance WHERE user_id NOT IN (
  SELECT id FROM users WHERE is_admin = TRUE
);

-- Step 5: Delete friendships involving non-admin users
DELETE FROM friendships WHERE user_id NOT IN (
  SELECT id FROM users WHERE is_admin = TRUE
)
OR friend_id NOT IN (
  SELECT id FROM users WHERE is_admin = TRUE
);

-- Step 6: Delete coin transactions for non-admin users
DELETE FROM coin_transactions WHERE user_id NOT IN (
  SELECT id FROM users WHERE is_admin = TRUE
);

-- Step 7: Delete player stats for non-admin users
DELETE FROM player_stats WHERE user_id NOT IN (
  SELECT id FROM users WHERE is_admin = TRUE
);

-- Step 8: Delete non-admin users (CASCADE will handle related data)
DELETE FROM users WHERE is_admin = FALSE;

-- Step 9: Clear migrations table to allow fresh migrations if needed (optional)
-- Uncomment if you want to reset migrations
-- DELETE FROM migrations;

-- Commit all changes
COMMIT;

-- Verify cleanup - should only show admin accounts
SELECT 'Remaining users:' as status, COUNT(*) as count FROM users;
SELECT username, email, is_admin FROM users;
SELECT 'Remaining rooms:' as status, COUNT(*) as count FROM rooms;
SELECT 'Remaining matches:' as status, COUNT(*) as count FROM matches;
SELECT 'Remaining friendships:' as status, COUNT(*) as count FROM friendships;
SELECT 'Remaining notifications:' as status, COUNT(*) as count FROM notifications;
SELECT 'Remaining payment transactions:' as status, COUNT(*) as count FROM payment_transactions;
SELECT 'Remaining coin transactions:' as status, COUNT(*) as count FROM coin_transactions;

-- ============================================================================
-- Database cleanup complete!
-- All non-admin user data has been removed.
-- ============================================================================
