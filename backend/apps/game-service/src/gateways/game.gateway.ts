import {
  WebSocketGateway,
  WebSocketServer,
  SubscribeMessage,
  ConnectedSocket,
  MessageBody,
  OnGatewayInit,
  OnGatewayConnection,
  OnGatewayDisconnect,
  WsException,
} from '@nestjs/websockets';
import { Server, Socket } from 'socket.io';
import { UseGuards, Logger } from '@nestjs/common';
import { JwtService } from '@nestjs/jwt';
import { GameService } from '../game.service';
import { RedisService } from '../../../libs/redis/src/redis.service';
import { JoinTableDto } from '../dto/join-table.dto';
import { DrawCardDto } from '../dto/draw-card.dto';
import { DiscardCardDto } from '../dto/discard-card.dto';
import { DeclareDto } from '../dto/declare.dto';

@WebSocketGateway({
  namespace: '/game',
  cors: {
    origin: process.env.ALLOWED_ORIGINS?.split(',') || '*',
    credentials: true,
  },
  transports: ['websocket'],
})
export class GameGateway
  implements OnGatewayInit, OnGatewayConnection, OnGatewayDisconnect
{
  @WebSocketServer() server: Server;
  private readonly logger = new Logger(GameGateway.name);

  constructor(
    private readonly jwtService: JwtService,
    private readonly gameService: GameService,
    private readonly redisService: RedisService,
  ) {}

  afterInit(server: Server) {
    server.use(async (socket: Socket, next) => {
      try {
        const token = socket.handshake.auth.token?.replace('Bearer ', '');
        if (!token) return next(new Error('AUTH_MISSING_TOKEN'));

        const payload = await this.jwtService.verifyAsync(token, {
          secret: process.env.JWT_SECRET,
        });

        socket.data.userId = payload.sub;
        socket.data.username = payload.username;
        socket.data.deviceId = socket.handshake.auth.device_id;

        // Mark user as online
        await this.redisService.setex(`user:online:${payload.sub}`, 300, '1');

        next();
      } catch {
        next(new Error('AUTH_INVALID_TOKEN'));
      }
    });
  }

  async handleConnection(client: Socket) {
    this.logger.log(`Client connected: ${client.data.userId}`);
    // Join personal room for direct messages
    client.join(`user:${client.data.userId}`);
  }

  async handleDisconnect(client: Socket) {
    const userId = client.data.userId;
    this.logger.log(`Client disconnected: ${userId}`);

    if (userId) {
      await this.redisService.del(`user:online:${userId}`);

      // Notify active table about disconnection
      const activeTable = await this.redisService.get(`player:table:${userId}`);
      if (activeTable) {
        this.server.to(`table:${activeTable}`).emit('player_disconnected', {
          user_id: userId,
          reconnect_timeout: 60,
        });

        // Start rejoin timer
        await this.gameService.startReconnectTimer(userId, activeTable);
      }
    }
  }

  @SubscribeMessage('join_table')
  async handleJoinTable(
    @ConnectedSocket() client: Socket,
    @MessageBody() dto: JoinTableDto,
  ) {
    const userId = client.data.userId;

    try {
      const state = await this.gameService.joinTable(userId, dto.table_id);

      client.join(`table:${dto.table_id}`);
      await this.redisService.setex(`player:table:${userId}`, 3600, dto.table_id);

      // Send full state to joining player
      client.emit('table_state', state);

      // Broadcast to others
      client.to(`table:${dto.table_id}`).emit('player_joined', {
        user_id: userId,
        username: client.data.username,
        seat: state.players.find((p) => p.user_id === userId)?.seat,
      });

      // Check if game can start
      if (state.can_start) {
        await this.gameService.startGame(dto.table_id);
        const gameStartPayload = await this.gameService.getGameStartPayload(
          dto.table_id,
          userId,
        );
        this.server.to(`table:${dto.table_id}`).emit('game_starting', {
          countdown: 3,
        });
        // Send personalized hands to each player
        await this.broadcastGameStart(dto.table_id);
      }
    } catch (err) {
      throw new WsException(err.message);
    }
  }

  @SubscribeMessage('draw_card')
  async handleDrawCard(
    @ConnectedSocket() client: Socket,
    @MessageBody() dto: DrawCardDto,
  ) {
    const userId = client.data.userId;

    try {
      const result = await this.gameService.drawCard(
        userId,
        dto.table_id,
        dto.source,
      );

      // Tell drawer what card they got
      client.emit('card_drawn', {
        source: dto.source,
        your_new_card: result.drawn_card,
        open_pile_top: result.open_pile_top,
      });

      // Tell others that a card was drawn (not revealing card)
      client.to(`table:${dto.table_id}`).emit('card_drawn', {
        user_id: userId,
        source: dto.source,
        open_pile_top: result.open_pile_top,
      });
    } catch (err) {
      throw new WsException(err.message);
    }
  }

  @SubscribeMessage('discard_card')
  async handleDiscardCard(
    @ConnectedSocket() client: Socket,
    @MessageBody() dto: DiscardCardDto,
  ) {
    const userId = client.data.userId;

    try {
      const result = await this.gameService.discardCard(
        userId,
        dto.table_id,
        dto.card,
      );

      // Broadcast discard to all
      this.server.to(`table:${dto.table_id}`).emit('card_discarded', {
        user_id: userId,
        card: dto.card,
        open_pile_top: result.open_pile_top,
        next_player: result.next_player_id,
      });

      // Notify next player it's their turn
      this.server.to(`user:${result.next_player_id}`).emit('your_turn', {
        time_limit: 30,
        open_pile_top: result.open_pile_top,
        valid_actions: ['draw_card'],
      });
    } catch (err) {
      throw new WsException(err.message);
    }
  }

  @SubscribeMessage('declare')
  async handleDeclare(
    @ConnectedSocket() client: Socket,
    @MessageBody() dto: DeclareDto,
  ) {
    const userId = client.data.userId;

    try {
      const result = await this.gameService.declare(
        userId,
        dto.table_id,
        dto.hand,
      );

      if (result.is_valid) {
        // Broadcast game over to all players
        this.server.to(`table:${dto.table_id}`).emit('game_over', result.game_over_payload);
        // Handle prize distribution in background
        await this.gameService.distributeWinnings(dto.table_id, result);
      } else {
        // Invalid declaration — penalize player
        this.server.to(`table:${dto.table_id}`).emit('invalid_declaration', {
          user_id: userId,
          penalty: 80,
        });
      }
    } catch (err) {
      throw new WsException(err.message);
    }
  }

  @SubscribeMessage('ping')
  async handlePing(@ConnectedSocket() client: Socket) {
    // Refresh online presence
    if (client.data.userId) {
      await this.redisService.setex(
        `user:online:${client.data.userId}`,
        300,
        '1',
      );
    }
    client.emit('pong', { server_time: Date.now() });
  }

  private async broadcastGameStart(tableId: string): Promise<void> {
    const players = await this.gameService.getTablePlayers(tableId);

    for (const player of players) {
      const hand = await this.gameService.getPlayerHand(tableId, player.user_id);
      const startPayload = await this.gameService.getGameStartPayload(
        tableId,
        player.user_id,
      );

      this.server.to(`user:${player.user_id}`).emit('game_started', {
        ...startPayload,
        your_hand: hand,
      });
    }
  }
}
