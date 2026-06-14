'use strict';

const { query } = require('../config/database');
const engine = require('../modules/game/game.engine');
const scoreEngine = require('../modules/game/score.engine');
const { getBotBid, getBotCard } = require('../modules/game/ai.bot');
const paymentService = require('../modules/payments/payment.service');
const logger = require('../config/logger');

// In-memory store of active game states keyed by roomId
const gameStates = new Map();
// Track which socket IDs belong to which userId + roomId
const userSockets = new Map(); // userId => socketId

// Personal room name — MUST match the format used in socket.manager.js: user:{userId}
const userRoom = (userId) => `user:${userId}`;

// ── Socket-level message throttle ─────────────────────────────────────────────
// Tracks per-socket: last send timestamp + rolling 60-second window count.
const _msgThrottle = new Map(); // socketId → { lastMs, windowStart, count }

const _envInt = (k, d) => { const v = parseInt(process.env[k], 10); return Number.isFinite(v) && v > 0 ? v : d; };
const THROTTLE_MIN_GAP_MS = _envInt('SOCKET_MSG_GAP_MS',   500); // SOCKET_MSG_GAP_MS=500
const THROTTLE_WINDOW_MS  = _envInt('SOCKET_MSG_WINDOW_MS', 60_000);
const THROTTLE_WINDOW_MAX = _envInt('SOCKET_MSG_MAX',        60); // SOCKET_MSG_MAX=60

function _isSocketThrottled(socketId) {
  const now = Date.now();
  const t   = _msgThrottle.get(socketId) || { lastMs: 0, windowStart: now, count: 0 };

  // Per-message gap check
  if (now - t.lastMs < THROTTLE_MIN_GAP_MS) return true;

  // Rolling window reset
  if (now - t.windowStart > THROTTLE_WINDOW_MS) {
    t.windowStart = now;
    t.count       = 0;
  }

  t.count++;
  t.lastMs = now;
  _msgThrottle.set(socketId, t);
  return t.count > THROTTLE_WINDOW_MAX;
}

const BOT_DELAY_MS = 1200; // simulate bot thinking
const DISCONNECT_GRACE_MS = _envInt('GAME_DISCONNECT_GRACE_MS', 12_000); // wait before treating a drop as a leave

// ─── Helpers ──────────────────────────────────────────────────────────────────

function safeHand(state, requestingSeat) {
  // Returns hands with other players' cards hidden
  const result = {};
  for (const [seat, hand] of Object.entries(state.hands)) {
    result[seat] = parseInt(seat) === requestingSeat ? hand : hand.map(() => ({ hidden: true }));
  }
  return result;
}

function publicState(state, forSeat) {
  return {
    roomId:       state.roomId,
    matchId:      state.matchId,
    round:        state.round,
    phase:        state.phase,
    dealer:       state.dealer,
    bids:         state.bids,
    tricksWon:    state.tricksWon,
    scores:       state.scores,
    currentTurn:  state.currentTurn,
    ledSuit:      state.ledSuit,
    currentTrick: state.currentTrick,
    players:      state.players,
    mySeat:       forSeat,
    hand:         state.hands[forSeat] || [],
  };
}

async function fetchRoomPlayers(roomId) {
  const result = await query(
    `SELECT rp.seat, rp.is_bot, rp.bot_level,
            u.id AS user_id, u.username, u.avatar_url
     FROM room_players rp
     LEFT JOIN users u ON u.id = rp.user_id
     WHERE rp.room_id = $1
     ORDER BY rp.seat`,
    [roomId]
  );
  return result.rows.map((r) => ({
    seat:     r.seat,
    userId:   r.user_id,
    username: r.is_bot ? `Bot (${r.bot_level})` : r.username,
    avatar:   r.avatar_url,
    isBot:    r.is_bot,
    botLevel: r.bot_level,
  }));
}

async function scheduleBotActions(io, roomId) {
  const state = gameStates.get(roomId);
  if (!state) return;

  if (state.phase === 'bidding') {
    const seat = state.currentTurn;
    const player = state.players[seat];
    if (!player?.isBot) return;

    setTimeout(async () => {
      const s = gameStates.get(roomId);
      if (!s || s.phase !== 'bidding' || s.currentTurn !== seat) return;
      let bid = 1;
      try { bid = getBotBid(s.hands[seat], player.botLevel); } catch (e) {
        logger.error('Bot bid calculation error', e);
      }
      // Clamp bid to valid range
      bid = Math.max(1, Math.min(13, Math.round(bid) || 1));
      try {
        engine.placeBid(s, seat, bid);
        gameStates.set(roomId, s);
        io.to(roomId).emit('bid_placed', { seat, bid });
        io.to(roomId).emit('game_state_update', { phase: s.phase, bids: s.bids, currentTurn: s.currentTurn });
        await scheduleBotActions(io, roomId);
      } catch (e) {
        logger.error('Bot bid error', e);
        setTimeout(() => scheduleBotActions(io, roomId), 500);
      }
    }, BOT_DELAY_MS);

  } else if (state.phase === 'playing') {
    const seat = state.currentTurn;
    const player = state.players[seat];
    if (!player?.isBot) return;

    setTimeout(async () => {
      const s = gameStates.get(roomId);
      if (!s || s.phase !== 'playing' || s.currentTurn !== seat) return;

      let card;
      try {
        card = getBotCard(
          s.hands[seat], s.currentTrick, s.ledSuit,
          s.bids, s.tricksWon, seat, player.botLevel
        );
      } catch (e) {
        logger.error('Bot card selection error, falling back to easy', e);
        // Safety fallback: pick first legal card
        const hand = s.hands[seat] || [];
        const led  = s.currentTrick.length === 0 ? null : s.ledSuit;
        const legalFallback = hand.filter((c) => {
          if (!led) return true;
          const hasSuit = hand.some((x) => x.suit === led);
          return hasSuit ? c.suit === led : true;
        });
        card = legalFallback.length ? legalFallback[0] : hand[0];
      }

      if (!card) {
        logger.error('Bot has no card to play at seat', seat);
        return;
      }

      try {
        const result = engine.playCard(s, seat, card);
        gameStates.set(roomId, result.state);
        io.to(roomId).emit('card_played', { seat, card });

        if (result.trickResult) {
          io.to(roomId).emit('trick_result', {
            plays:      result.trickResult.plays,
            winnerSeat: result.trickResult.winnerSeat,
            ledSuit:    result.trickResult.ledSuit,
            tricksWon:  result.state.tricksWon,
          });

          if (result.roundOver) {
            await handleRoundEnd(io, roomId, result.state, result.roundScores);
            return;
          }
        }
        io.to(roomId).emit('game_state_update', {
          phase:        result.state.phase,
          currentTurn:  result.state.currentTurn,
          tricksWon:    result.state.tricksWon,
          currentTrick: result.state.currentTrick,
          ledSuit:      result.state.ledSuit,
        });
        await scheduleBotActions(io, roomId);
      } catch (e) {
        logger.error('Bot play error', e);
        // Retry in 500ms with a safe fallback card to avoid game freeze
        setTimeout(() => scheduleBotActions(io, roomId), 500);
      }
    }, BOT_DELAY_MS);
  }
}

// Marks a seat as abandoned, transfers the host crown if the leaver was host,
// and notifies the room so the (possibly new) host can drop in a bot.
async function markPlayerLeft(io, roomId, seat) {
  const state = gameStates.get(roomId);
  if (!state) return;
  const player = state.players[seat];
  if (!player || player.isBot || player.left) return;

  player.left = true;
  gameStates.set(roomId, state);

  let hostId = null;
  try {
    const r = await query('SELECT host_id FROM rooms WHERE id = $1', [roomId]);
    hostId = r.rows[0]?.host_id || null;
    // Leaver was the host → pass the crown to another present, real player.
    if (hostId && hostId === player.userId) {
      const next = state.players.find(
        (p) => !p.isBot && !p.left && p.userId && p.userId !== player.userId
      );
      if (next) {
        hostId = next.userId;
        await query('UPDATE rooms SET host_id = $1 WHERE id = $2', [hostId, roomId]);
      }
    }
  } catch (e) {
    logger.error('markPlayerLeft host lookup', e);
  }

  io.to(roomId).emit('player_left_game', {
    seat,
    userId:   player.userId,
    username: player.username,
    hostId,
  });
}

async function handleRoundEnd(io, roomId, state, roundScores) {
  // Persist round to DB
  if (state.matchId) {
    await scoreEngine.persistRound(
      state.matchId, state.round,
      (state.dealer - 1 + 4) % 4,
      state.bids, state.tricksWon
    );
  }

  io.to(roomId).emit('round_result', {
    round:       state.round,
    roundScores,
    totalScores: state.scores,
  });

  if (state.phase === 'game_end') {
    await handleGameEnd(io, roomId, state);
  }
}

async function handleGameEnd(io, roomId, state) {
  const winnerSeat = engine.getGameWinner(state);
  const winner = state.players[winnerSeat];

  let playerRewards = {};
  if (state.matchId) {
    await scoreEngine.persistMatch(
      state.matchId, winner.userId, state.scores, state.players
    );
    playerRewards = await scoreEngine.updatePlayerStats(state.players, state.scores, winnerSeat);
  }

  // Settle bets — only if real winner has a userId (not a bot)
  let betResult = null;
  if (state.matchId && winner.userId && !winner.isBot) {
    try {
      betResult = await paymentService.payoutWinner(roomId, state.matchId, winner.userId);
    } catch (err) {
      logger.error('Bet payout failed', err);
    }
  }

  io.to(roomId).emit('game_result', {
    winnerSeat,
    winnerName:    winner.username,
    finalScores:   state.scores,
    roundScores:   state.roundScores,
    playerRewards,
    betResult:     betResult
      ? { betAmount: betResult.betAmount, totalPot: betResult.totalPot, winnerUserId: betResult.winnerUserId }
      : null,
  });

  // Notify all connected clients so leaderboard / profile pages can auto-refresh
  io.emit('leaderboard_updated');

  await query(`UPDATE rooms SET status = 'finished' WHERE id = $1`, [roomId]);
  gameStates.delete(roomId);
}

// ─── Socket event handlers ────────────────────────────────────────────────────

function registerGameSocket(io, socket) {
  const { userId } = socket;
  userSockets.set(userId, socket.id);
  // Join personal room so payment events can target this user directly
  socket.join(userRoom(userId));

  // ── Join room channel ──
  socket.on('join_room', async ({ roomId }) => {
    try {
      const room = await query('SELECT id, status, host_id FROM rooms WHERE id = $1', [roomId]);
      if (!room.rows.length) return socket.emit('error', { message: 'Room not found' });

      socket.join(roomId);
      socket.roomId = roomId;

      // If game is active, send current state
      const state = gameStates.get(roomId);
      if (state) {
        const seat = state.players.findIndex((p) => p.userId === userId);
        // A previously-abandoned player came back → reclaim their seat and
        // tell the host so the "add a bot" prompt can stop.
        if (seat !== -1 && state.players[seat].left) {
          state.players[seat].left = false;
          gameStates.set(roomId, state);
          io.to(roomId).emit('player_rejoined_game', {
            seat, userId, username: socket.username,
          });
        }
        socket.emit('game_state_sync', publicState(state, seat));
      }

      io.to(roomId).emit('player_joined', { userId, username: socket.username });
      // Tell everyone in the room to reload the roster (covers seat/host/bot changes).
      io.to(roomId).emit('room_updated', { roomId });
    } catch (err) {
      logger.error('join_room error', err);
      socket.emit('error', { message: 'Failed to join room' });
    }
  });

  // ── Leave room channel (does not remove the player from the DB roster) ──
  socket.on('leave_room', ({ roomId }) => {
    if (!roomId) return;
    socket.leave(roomId);
    if (socket.roomId === roomId) socket.roomId = null;
  });

  // ── Leave an ACTIVE game mid-match (explicit) ──
  // Marks the seat as abandoned, notifies everyone, and asks the host to drop
  // in a bot. The game resumes from the exact point the player left.
  socket.on('leave_game', async ({ roomId }) => {
    const state = gameStates.get(roomId);
    if (!state) return;
    const seat = state.players.findIndex((p) => p.userId === userId && !p.isBot && !p.left);
    if (seat === -1) return;
    socket.leave(roomId);
    await markPlayerLeft(io, roomId, seat);
  });

  // ── Host replaces an abandoned seat with a medium bot, game continues ──
  socket.on('replace_with_bot', async ({ roomId, seat }) => {
    const state = gameStates.get(roomId);
    if (!state) return;
    try {
      const r = await query('SELECT host_id FROM rooms WHERE id = $1', [roomId]);
      if (r.rows[0]?.host_id !== userId) {
        return socket.emit('error', { message: 'Only the host can add a bot' });
      }
    } catch { return; }

    const player = state.players[seat];
    if (!player || player.isBot) return;

    player.isBot    = true;
    player.botLevel = 'medium';
    player.username = 'Bot (Medium)';
    player.left     = false;
    player.userId   = null; // bot has no account — payouts skip it
    gameStates.set(roomId, state);

    io.to(roomId).emit('player_replaced_by_bot', {
      seat, username: player.username, botLevel: 'medium',
    });

    // Resume play. If it's this seat's turn (or becomes its turn) the bot acts.
    await scheduleBotActions(io, roomId);
  });

  // ── Detect drop-outs (app closed / killed) during an active game ──
  // Reconnection re-joins the room within a short window, so we wait a grace
  // period and only treat it as a leave if the player is still gone.
  socket.on('disconnect', () => {
    const roomId = socket.roomId;
    if (!roomId) return;
    const state = gameStates.get(roomId);
    if (!state) return;
    const seat = state.players.findIndex((p) => p.userId === userId && !p.isBot && !p.left);
    if (seat === -1) return;

    setTimeout(() => {
      const s = gameStates.get(roomId);
      if (!s) return;
      const p = s.players[seat];
      if (!p || p.isBot || p.left) return;
      // Reconnected? A live socket for this user is back in the room → ignore.
      const sid  = userSockets.get(userId);
      const sock = sid ? io.sockets.sockets.get(sid) : null;
      if (sock && sock.connected && sock.rooms.has(roomId)) return;
      markPlayerLeft(io, roomId, seat).catch((e) => logger.error('markPlayerLeft', e));
    }, DISCONNECT_GRACE_MS);
  });

  // ── Start game ──
  socket.on('start_game', async ({ roomId }) => {
    try {
      const roomData = await query(
        'SELECT host_id, status FROM rooms WHERE id = $1', [roomId]
      );
      if (!roomData.rows.length) return socket.emit('error', { message: 'Room not found' });
      if (roomData.rows[0].host_id !== userId) return socket.emit('error', { message: 'Only host can start' });
      if (roomData.rows[0].status !== 'waiting') return socket.emit('error', { message: 'Game already started' });

      const players = await fetchRoomPlayers(roomId);
      if (players.length !== 4) return socket.emit('error', { message: 'Need exactly 4 players' });

      const matchId = await scoreEngine.createMatch(roomId);

      // Escrow bets from real players (fails fast if any player has insufficient balance)
      let betInfo = { betAmount: 0, totalPot: 0 };
      try {
        betInfo = await paymentService.escrowBets(roomId, matchId);
      } catch (betErr) {
        return socket.emit('error', { message: betErr.message || 'Failed to escrow bets' });
      }

      const state = engine.createGameState(roomId, players);
      state.matchId  = matchId;
      state.betAmount = betInfo.betAmount;
      engine.startRound(state);
      gameStates.set(roomId, state);

      io.to(roomId).emit('game_started', {
        matchId,
        betAmount: betInfo.betAmount,
        totalPot:  betInfo.totalPot,
        round:   state.round,
        players: players.map((p) => ({
          seat:     p.seat,
          userId:   p.userId,
          username: p.username,
          avatar:   p.avatar,
          isBot:    p.isBot,
          botLevel: p.botLevel,
        })),
      });

      // Send each player their hand
      for (const player of players) {
        if (player.isBot) continue;
        const targetSocketId = userSockets.get(player.userId);
        if (targetSocketId) {
          io.to(targetSocketId).emit('deal_cards', {
            hand: state.hands[player.seat],
            seat: player.seat,
          });
        }
      }

      io.to(roomId).emit('bidding_started', {
        round:       state.round,
        currentTurn: state.currentTurn,
        dealer:      state.dealer,
      });

      await scheduleBotActions(io, roomId);
    } catch (err) {
      logger.error('start_game error', err);
      socket.emit('error', { message: 'Failed to start game' });
    }
  });

  // ── Place bid ──
  socket.on('place_bid', ({ roomId, bid }) => {
    try {
      const state = gameStates.get(roomId);
      if (!state) return socket.emit('error', { message: 'No active game' });

      const seat = state.players.findIndex((p) => p.userId === userId);
      if (seat === -1) return socket.emit('error', { message: 'You are not in this game' });

      engine.placeBid(state, seat, bid);
      gameStates.set(roomId, state);

      io.to(roomId).emit('bid_placed', { seat, bid });
      io.to(roomId).emit('game_state_update', {
        phase:       state.phase,
        bids:        state.bids,
        currentTurn: state.currentTurn,
      });

      scheduleBotActions(io, roomId);
    } catch (err) {
      socket.emit('error', { message: err.message });
    }
  });

  // ── Play card ──
  socket.on('play_card', async ({ roomId, card }) => {
    try {
      const state = gameStates.get(roomId);
      if (!state) return socket.emit('error', { message: 'No active game' });

      const seat = state.players.findIndex((p) => p.userId === userId);
      if (seat === -1) return socket.emit('error', { message: 'Not in this game' });

      const result = engine.playCard(state, seat, card);
      gameStates.set(roomId, result.state);

      io.to(roomId).emit('card_played', { seat, card });

      if (result.trickResult) {
        io.to(roomId).emit('trick_result', {
          plays:      result.trickResult.plays,
          winnerSeat: result.trickResult.winnerSeat,
          ledSuit:    result.trickResult.ledSuit,
          tricksWon:  result.state.tricksWon,
        });

        if (result.roundOver) {
          await handleRoundEnd(io, roomId, result.state, result.roundScores);
          return;
        }
      }

      io.to(roomId).emit('game_state_update', {
        phase:        result.state.phase,
        currentTurn:  result.state.currentTurn,
        tricksWon:    result.state.tricksWon,
        currentTrick: result.state.currentTrick,
        ledSuit:      result.state.ledSuit,
      });

      await scheduleBotActions(io, roomId);
    } catch (err) {
      socket.emit('error', { message: err.message });
    }
  });

  // ── Start next round (called by host after round_end screen) ──
  socket.on('next_round', async ({ roomId }) => {
    try {
      const state = gameStates.get(roomId);
      if (!state || state.phase !== 'round_end') return;

      engine.startRound(state);
      gameStates.set(roomId, state);

      for (const player of state.players) {
        if (player.isBot) continue;
        const targetSocketId = userSockets.get(player.userId);
        if (targetSocketId) {
          io.to(targetSocketId).emit('deal_cards', {
            hand: state.hands[player.seat],
            seat: player.seat,
          });
        }
      }

      io.to(roomId).emit('bidding_started', {
        round:       state.round,
        currentTurn: state.currentTurn,
        dealer:      state.dealer,
      });

      await scheduleBotActions(io, roomId);
    } catch (err) {
      socket.emit('error', { message: err.message });
    }
  });

  // ── Reconnect ──
  socket.on('reconnect_player', async ({ roomId }) => {
    try {
      socket.join(roomId);
      socket.roomId = roomId;
      userSockets.set(userId, socket.id);

      const state = gameStates.get(roomId);
      if (!state) return socket.emit('error', { message: 'No active game' });

      const seat = state.players.findIndex((p) => p.userId === userId);
      socket.emit('game_state_sync', publicState(state, seat));
    } catch (err) {
      socket.emit('error', { message: 'Reconnect failed' });
    }
  });

  // ── In-game chat ──
  socket.on('chat_message', ({ roomId, message }) => {
    if (!message || message.length > 200) return;
    io.to(roomId).emit('chat_message', {
      userId,
      username:  socket.username,
      message:   message.trim(),
      timestamp: Date.now(),
    });
  });

  // ── Private in-game DM (ephemeral — only sender + target see it) ──
  socket.on('game_dm', ({ toUserId, text }) => {
    if (!text || !toUserId || text.length > 200) return;
    if (_isSocketThrottled(socket.id)) return;
    const payload = {
      from:     userId,
      fromName: socket.username,
      to:       toUserId,
      text:     text.trim(),
      ts:       Date.now(),
    };
    const targetSid = userSockets.get(toUserId);
    if (targetSid) io.to(targetSid).emit('game_dm', payload); // deliver to target
    socket.emit('game_dm', payload);                          // echo to sender for history
  });

  // ── Emoji reaction ──
  socket.on('send_emoji', ({ roomId, emoji }) => {
    io.to(roomId).emit('emoji_reaction', { userId, emoji });
  });

  // ── Direct message between users ──
  socket.on('private_message', async ({ toUserId, text }) => {
    if (!text?.trim() || !toUserId) return;
    if (_isSocketThrottled(socket.id)) {
      socket.emit('error', { message: 'Sending too fast. Please slow down.' });
      return;
    }
    try {
      const msgService = require('../modules/messages/message.service');
      const { sendNotification } = require('../modules/notifications/notification.service');

      const msg = await msgService.sendMessage(userId, toUserId, text.trim());

      const payload = {
        id:          msg.id,
        sender_id:   msg.sender_id,
        sender_name: socket.username,
        receiver_id: msg.receiver_id,
        text:        msg.text,
        is_read:     false,
        created_at:  msg.created_at,
      };

      // Deliver to recipient only — sender's screen handles the message locally
      io.to(userRoom(toUserId)).emit('private_message', payload);

      // In-app notification record
      query(
        `INSERT INTO notifications (user_id, type, title, body, data)
         VALUES ($1, 'private_message', $2, $3, $4)`,
        [toUserId, socket.username,
         text.trim().substring(0, 100),
         JSON.stringify({ fromUserId: userId, messageId: msg.id })]
      ).catch(() => {});

      // FCM push notification so recipient gets alerted when app is in background
      sendNotification(
        toUserId,
        socket.username,                        // notification title = sender username
        text.trim().substring(0, 100),          // notification body  = message preview
        {
          type:        'MESSAGE_RECEIVED',       // matches Flutter _handleMessage check
          senderId:    userId,
          senderName:  socket.username,
          messageText: text.trim().substring(0, 100),
        },
        'default_channel'
      ).catch(() => {});
    } catch (err) {
      logger.error('private_message error', err);
    }
  });

  // ── Game invite ──
  socket.on('send_game_invite', async ({ toUserId, roomId, roomCode }) => {
    if (!toUserId || !roomId) return;
    try {
      const { sendNotification } = require('../modules/notifications/notification.service');

      // In-app notification record
      await query(
        `INSERT INTO notifications (user_id, type, title, body, data)
         VALUES ($1, 'game_invite', $2, $3, $4)`,
        [toUserId,
         `${socket.username} invited you!`,
         `${socket.username} invited you to join room ${roomCode}`,
         JSON.stringify({ fromUserId: userId, roomId, roomCode })]
      );

      // Real-time socket delivery
      io.to(userRoom(toUserId)).emit('game_invite', {
        fromUserId: userId,
        fromUsername: socket.username,
        roomId,
        roomCode,
      });

      // FCM push so recipient sees it even when app is in background
      sendNotification(
        toUserId,
        `🎮 ${socket.username} invited you!`,
        `Join room ${roomCode} — tap to play`,
        {
          type:         'GAME_INVITE',
          fromUserId:   userId,
          fromUsername: socket.username,
          roomId,
          roomCode,
        },
        'room_channel'
      ).catch(() => {});
    } catch (err) {
      logger.error('send_game_invite error', err);
    }
  });

  // ── Leave room ──
  socket.on('leave_room', ({ roomId }) => {
    socket.leave(roomId);
    io.to(roomId).emit('player_left', { userId, username: socket.username });
  });

  socket.on('disconnect', () => {
    userSockets.delete(userId);
    _msgThrottle.delete(socket.id); // clean up throttle state
    if (socket.roomId) {
      io.to(socket.roomId).emit('player_disconnected', { userId, username: socket.username });
      // If game was never started (no active state), refund any escrowed bets
      if (!gameStates.has(socket.roomId)) {
        paymentService.refundBets(socket.roomId).catch((e) =>
          logger.error('Bet refund on disconnect failed', e)
        );
      }
    }
  });
}

module.exports = { registerGameSocket, userSockets };
