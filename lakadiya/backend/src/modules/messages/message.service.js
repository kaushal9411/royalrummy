const { query } = require('../../config/database');

// Create table + index on startup
query(`
  CREATE TABLE IF NOT EXISTS messages (
    id          SERIAL PRIMARY KEY,
    sender_id   UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    receiver_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    text        TEXT NOT NULL CHECK (char_length(text) BETWEEN 1 AND 500),
    is_read     BOOLEAN DEFAULT FALSE,
    created_at  TIMESTAMPTZ DEFAULT NOW()
  )
`).catch(() => {});

query(`
  CREATE INDEX IF NOT EXISTS idx_messages_pair_time
  ON messages (LEAST(sender_id::text, receiver_id::text), GREATEST(sender_id::text, receiver_id::text), created_at DESC)
`).catch(() => {});

// ── Get paginated message history between two users ───────────────────────────
const getConversation = async (userId, otherUserId, limit = 50, beforeId = null) => {
  const params = [userId, otherUserId, limit];
  const beforeClause = beforeId ? `AND m.id < $${params.push(beforeId)}` : '';

  const result = await query(
    `SELECT m.id, m.sender_id, m.receiver_id, m.text, m.is_read, m.created_at,
            u.username AS sender_name, u.avatar_url AS sender_avatar
     FROM messages m
     JOIN users u ON u.id = m.sender_id
     WHERE ((m.sender_id = $1 AND m.receiver_id = $2)
         OR (m.sender_id = $2 AND m.receiver_id = $1))
     ${beforeClause}
     ORDER BY m.created_at DESC
     LIMIT $3`,
    params
  );
  return result.rows.reverse(); // oldest first for display
};

// ── Send a message ────────────────────────────────────────────────────────────
const sendMessage = async (senderId, receiverId, text) => {
  const result = await query(
    `INSERT INTO messages (sender_id, receiver_id, text)
     VALUES ($1, $2, $3) RETURNING *`,
    [senderId, receiverId, text.trim()]
  );
  return result.rows[0];
};

// ── Mark messages from otherUser as read ─────────────────────────────────────
const markRead = async (userId, otherUserId) => {
  await query(
    `UPDATE messages SET is_read = TRUE
     WHERE receiver_id = $1 AND sender_id = $2 AND is_read = FALSE`,
    [userId, otherUserId]
  );
};

// ── List all conversations for a user (most recent message per partner) ───────
const getConversationList = async (userId) => {
  const result = await query(
    `WITH ranked AS (
       SELECT
         CASE WHEN m.sender_id = $1 THEN m.receiver_id ELSE m.sender_id END AS other_id,
         m.text       AS last_text,
         m.created_at AS last_at,
         m.sender_id  AS last_sender_id,
         ROW_NUMBER() OVER (
           PARTITION BY CASE WHEN m.sender_id = $1 THEN m.receiver_id ELSE m.sender_id END
           ORDER BY m.created_at DESC
         ) AS rn
       FROM messages m
       WHERE m.sender_id = $1 OR m.receiver_id = $1
     )
     SELECT
       r.other_id,
       u.username  AS other_name,
       u.avatar_url AS other_avatar,
       u.level      AS other_level,
       r.last_text,
       r.last_at,
       r.last_sender_id,
       (SELECT COUNT(*) FROM messages
        WHERE receiver_id = $1 AND sender_id = r.other_id AND is_read = FALSE
       )::int AS unread_count
     FROM ranked r
     JOIN users u ON u.id = r.other_id
     WHERE r.rn = 1
     ORDER BY r.last_at DESC`,
    [userId]
  );
  return result.rows;
};

// ── Total unread count for a user ────────────────────────────────────────────
const getTotalUnread = async (userId) => {
  const result = await query(
    `SELECT COUNT(*)::int AS count FROM messages WHERE receiver_id = $1 AND is_read = FALSE`,
    [userId]
  );
  return result.rows[0].count;
};

module.exports = { getConversation, sendMessage, markRead, getConversationList, getTotalUnread };
