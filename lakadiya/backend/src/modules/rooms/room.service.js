const { query, getClient } = require('../../config/database');
const { v4: uuidv4 } = require('uuid');

const VALID_BET_AMOUNTS = [0, 10, 25, 50, 100];

const _getUserBalance = async (userId) => {
  const r = await query(
    `SELECT COALESCE(
       SUM(CASE WHEN type IN ('add','bet_win')        AND status='success' THEN amount ELSE 0 END) -
       SUM(CASE WHEN type IN ('withdraw','bet_deduct') AND status='success' THEN amount ELSE 0 END),
     0)::float AS balance
     FROM payment_transactions WHERE user_id = $1`,
    [userId]
  );
  return parseFloat(r.rows[0]?.balance) || 0;
};

const generateCode = () =>
  Math.random().toString(36).substring(2, 8).toUpperCase();

const createRoom = async (hostId, isPrivate = false, betAmount = 0) => {
  const safeBet = VALID_BET_AMOUNTS.includes(Number(betAmount)) ? Number(betAmount) : 0;

  // If paid room, validate host's wallet balance
  if (safeBet > 0) {
    const balance = await _getUserBalance(hostId);
    if (balance <= 100) throw { status: 400, message: 'You need a wallet balance above ₹100 to create a bet game' };
    if (balance < safeBet) throw { status: 400, message: `Insufficient wallet balance to create a ₹${safeBet} bet game` };
  }

  let code;
  let attempts = 0;
  do {
    code = generateCode();
    const exists = await query('SELECT id FROM rooms WHERE code = $1', [code]);
    if (!exists.rows.length) break;
    attempts++;
  } while (attempts < 10);

  const result = await query(
    `INSERT INTO rooms (code, host_id, is_private, bet_amount) VALUES ($1, $2, $3, $4)
     RETURNING id, code, host_id, status, is_private, bet_amount, created_at`,
    [code, hostId, isPrivate, safeBet]
  );
  const room = result.rows[0];

  await query(
    'INSERT INTO room_players (room_id, user_id, seat) VALUES ($1, $2, $3)',
    [room.id, hostId, 0]
  );
  return room;
};

const joinRoom = async (userId, code) => {
  const roomResult = await query(
    'SELECT id, status, bet_amount FROM rooms WHERE code = $1',
    [code.toUpperCase()]
  );
  if (!roomResult.rows.length) throw { status: 404, message: 'Room not found' };

  const room = roomResult.rows[0];
  if (room.status !== 'waiting') throw { status: 400, message: 'Room not accepting players' };

  // Wallet check for paid rooms
  const betAmount = parseFloat(room.bet_amount) || 0;
  if (betAmount > 0) {
    const balance = await _getUserBalance(userId);
    if (balance <= 100) throw { status: 400, message: 'You need a wallet balance above ₹100 to join this bet game' };
    if (balance < betAmount) throw { status: 400, message: `Insufficient wallet balance. Need ₹${betAmount} to join this game` };
  }

  const players = await query(
    'SELECT seat, user_id FROM room_players WHERE room_id = $1',
    [room.id]
  );
  if (players.rows.length >= 4) throw { status: 400, message: 'Room is full' };

  const alreadyIn = players.rows.find((p) => p.user_id === userId);
  if (alreadyIn) return getRoomDetails(room.id);

  const occupiedSeats = new Set(players.rows.map((p) => p.seat));
  let seat = 0;
  while (occupiedSeats.has(seat)) seat++;

  await query(
    'INSERT INTO room_players (room_id, user_id, seat) VALUES ($1, $2, $3)',
    [room.id, userId, seat]
  );
  return getRoomDetails(room.id);
};

const getRoomDetails = async (roomId) => {
  const room = await query(
    `SELECT r.id, r.code, r.status, r.is_private, r.bet_amount, r.host_id,
            u.username AS host_name
     FROM rooms r JOIN users u ON u.id = r.host_id
     WHERE r.id = $1`,
    [roomId]
  );
  if (!room.rows.length) throw { status: 404, message: 'Room not found' };

  const players = await query(
    `SELECT rp.seat, rp.is_bot, rp.bot_level,
            u.id AS user_id, u.username, u.avatar_url, u.level
     FROM room_players rp
     LEFT JOIN users u ON u.id = rp.user_id
     WHERE rp.room_id = $1
     ORDER BY rp.seat`,
    [roomId]
  );
  return { ...room.rows[0], players: players.rows };
};

const leaveRoom = async (userId, roomId) => {
  await query(
    'DELETE FROM room_players WHERE room_id = $1 AND user_id = $2',
    [roomId, userId]
  );
  const remaining = await query(
    'SELECT user_id FROM room_players WHERE room_id = $1 AND is_bot = FALSE',
    [roomId]
  );
  if (!remaining.rows.length) {
    await query('UPDATE rooms SET status = $1 WHERE id = $2', ['finished', roomId]);
  } else {
    const room = await query('SELECT host_id FROM rooms WHERE id = $1', [roomId]);
    if (room.rows[0].host_id === userId) {
      const newHost = remaining.rows[0].user_id;
      await query('UPDATE rooms SET host_id = $1 WHERE id = $2', [newHost, roomId]);
    }
  }
};

const addBot = async (hostId, roomId, botLevel = 'medium') => {
  const room = await query('SELECT host_id FROM rooms WHERE id = $1', [roomId]);
  if (!room.rows.length) throw { status: 404, message: 'Room not found' };
  if (room.rows[0].host_id !== hostId) throw { status: 403, message: 'Only host can add bots' };

  const players = await query(
    'SELECT seat FROM room_players WHERE room_id = $1',
    [roomId]
  );
  if (players.rows.length >= 4) throw { status: 400, message: 'Room is full' };

  const occupiedSeats = new Set(players.rows.map((p) => p.seat));
  let seat = 0;
  while (occupiedSeats.has(seat)) seat++;

  await query(
    'INSERT INTO room_players (room_id, seat, is_bot, bot_level) VALUES ($1, $2, TRUE, $3)',
    [roomId, seat, botLevel]
  );
  return getRoomDetails(roomId);
};

const getPublicRooms = async () => {
  const result = await query(
    `SELECT r.id, r.code, r.status, r.bet_amount,
            u.username AS host_name,
            COUNT(rp.seat) AS player_count
     FROM rooms r
     JOIN users u ON u.id = r.host_id
     LEFT JOIN room_players rp ON rp.room_id = r.id
     WHERE r.is_private = FALSE AND r.status = 'waiting'
     GROUP BY r.id, u.username
     HAVING COUNT(rp.seat) < 4
     ORDER BY r.created_at DESC
     LIMIT 20`,
    []
  );
  return result.rows;
};

const resetBet = async (hostId, roomId) => {
  const room = await query('SELECT host_id FROM rooms WHERE id = $1', [roomId]);
  if (!room.rows.length) throw { status: 404, message: 'Room not found' };
  if (room.rows[0].host_id !== hostId) throw { status: 403, message: 'Only host can reset bet' };
  await query("UPDATE rooms SET bet_amount = 0 WHERE id = $1", [roomId]);
};

module.exports = { createRoom, joinRoom, getRoomDetails, leaveRoom, addBot, getPublicRooms, resetBet };
