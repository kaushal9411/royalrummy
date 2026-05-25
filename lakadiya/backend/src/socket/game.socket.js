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

const BOT_DELAY_MS = 1200; // simulate bot thinking

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
      const bid = getBotBid(s.hands[seat], player.botLevel);
      try {
        engine.placeBid(s, seat, bid);
        gameStates.set(roomId, s);
        io.to(roomId).emit('bid_placed', { seat, bid });
        io.to(roomId).emit('game_state_update', { phase: s.phase, bids: s.bids, currentTurn: s.currentTurn });
        await scheduleBotActions(io, roomId);
      } catch (e) {
        logger.error('Bot bid error', e);
      }
    }, BOT_DELAY_MS);

  } else if (state.phase === 'playing') {
    const seat = state.currentTurn;
    const player = state.players[seat];
    if (!player?.isBot) return;

    setTimeout(async () => {
      const s = gameStates.get(roomId);
      if (!s || s.phase !== 'playing' || s.currentTurn !== seat) return;
      const card = getBotCard(
        s.hands[seat], s.currentTrick, s.ledSuit,
        s.bids, s.tricksWon, seat, player.botLevel
      );
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
      }
    }, BOT_DELAY_MS);
  }
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

  if (state.matchId) {
    await scoreEngine.persistMatch(
      state.matchId, winner.userId, state.scores, state.players
    );
    await scoreEngine.updatePlayerStats(state.players, state.scores, winnerSeat);
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
    winnerName:  winner.username,
    finalScores: state.scores,
    roundScores: state.roundScores,
    betResult:   betResult
      ? { betAmount: betResult.betAmount, totalPot: betResult.totalPot, winnerUserId: betResult.winnerUserId }
      : null,
  });

  await query(`UPDATE rooms SET status = 'finished' WHERE id = $1`, [roomId]);
  gameStates.delete(roomId);
}

// ─── Socket event handlers ────────────────────────────────────────────────────

function registerGameSocket(io, socket) {
  const { userId } = socket;
  userSockets.set(userId, socket.id);

  // ── Join room channel ──
  socket.on('join_room', async ({ roomId }) => {
    try {
      const room = await query('SELECT id, status FROM rooms WHERE id = $1', [roomId]);
      if (!room.rows.length) return socket.emit('error', { message: 'Room not found' });

      socket.join(roomId);
      socket.roomId = roomId;

      // If game is active, send current state
      const state = gameStates.get(roomId);
      if (state) {
        const seat = state.players.findIndex((p) => p.userId === userId);
        socket.emit('game_state_sync', publicState(state, seat));
      }

      io.to(roomId).emit('player_joined', { userId, username: socket.username });
    } catch (err) {
      logger.error('join_room error', err);
      socket.emit('error', { message: 'Failed to join room' });
    }
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

  // ── Emoji reaction ──
  socket.on('send_emoji', ({ roomId, emoji }) => {
    io.to(roomId).emit('emoji_reaction', { userId, emoji });
  });

  // ── Leave room ──
  socket.on('leave_room', ({ roomId }) => {
    socket.leave(roomId);
    io.to(roomId).emit('player_left', { userId, username: socket.username });
  });

  socket.on('disconnect', () => {
    userSockets.delete(userId);
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

module.exports = { registerGameSocket };
