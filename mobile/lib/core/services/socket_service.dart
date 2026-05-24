import 'dart:async';
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;
import '../storage/secure_storage.dart';
import '../constants/app_constants.dart';

final socketServiceProvider = Provider<SocketService>((ref) {
  return SocketService(ref);
});

enum SocketStatus { disconnected, connecting, connected, reconnecting }

class SocketService {
  late IO.Socket _socket;
  final Ref _ref;
  final _statusController = StreamController<SocketStatus>.broadcast();
  final _eventController = StreamController<Map<String, dynamic>>.broadcast();

  Stream<SocketStatus> get statusStream => _statusController.stream;
  Stream<Map<String, dynamic>> get eventStream => _eventController.stream;

  SocketService(this._ref);

  Future<void> connect() async {
    final token = await _ref.read(secureStorageProvider).getAccessToken();

    _socket = IO.io(
      '${AppConstants.wsBaseUrl}/game',
      IO.OptionBuilder()
          .setTransports(['websocket'])
          .setAuth({'token': 'Bearer $token'})
          .setExtraHeaders({'X-Device-ID': await _ref.read(secureStorageProvider).getDeviceId()})
          .enableAutoConnect()
          .enableReconnection()
          .setReconnectionAttempts(10)
          .setReconnectionDelay(1000)
          .setReconnectionDelayMax(10000)
          .build(),
    );

    _setupListeners();
    _statusController.add(SocketStatus.connecting);
  }

  void _setupListeners() {
    _socket.onConnect((_) {
      _statusController.add(SocketStatus.connected);
      _startHeartbeat();
    });

    _socket.onDisconnect((_) {
      _statusController.add(SocketStatus.disconnected);
      _stopHeartbeat();
    });

    _socket.onReconnecting((_) {
      _statusController.add(SocketStatus.reconnecting);
    });

    _socket.onError((err) {
      _eventController.add({'type': 'error', 'data': err});
    });

    // Game events
    final gameEvents = [
      'table_state', 'player_joined', 'player_left', 'game_starting',
      'game_started', 'your_turn', 'player_turn', 'card_drawn',
      'card_discarded', 'turn_timer', 'player_dropped', 'game_over',
      'invalid_declaration', 'player_reconnected', 'player_disconnected',
      'new_message', 'score_update',
    ];

    for (final event in gameEvents) {
      _socket.on(event, (data) {
        _eventController.add({'type': event, 'data': data});
      });
    }

    _socket.on('pong', (data) {
      // Latency tracking
    });
  }

  // ── Actions ──────────────────────────────────────────────────────────────
  void joinTable(String tableId) {
    _emit('join_table', {'table_id': tableId});
  }

  void drawCard(String tableId, String source) {
    _emit('draw_card', {'table_id': tableId, 'source': source});
  }

  void discardCard(String tableId, String card) {
    _emit('discard_card', {'table_id': tableId, 'card': card});
  }

  void declare(String tableId, Map<String, dynamic> hand) {
    _emit('declare', {'table_id': tableId, 'hand': hand});
  }

  void dropGame(String tableId) {
    _emit('drop_game', {'table_id': tableId});
  }

  void sendMessage(String roomId, String message, {String type = 'text'}) {
    _emit('send_message', {'room_id': roomId, 'message': message, 'type': type});
  }

  // ── Heartbeat ─────────────────────────────────────────────────────────────
  Timer? _heartbeatTimer;

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (_socket.connected) {
        _socket.emit('ping', {});
      }
    });
  }

  void _stopHeartbeat() {
    _heartbeatTimer?.cancel();
  }

  void _emit(String event, Map<String, dynamic> data) {
    if (_socket.connected) {
      _socket.emit(event, data);
    } else {
      // Queue for retry on reconnect
      _socket.once('connect', (_) => _socket.emit(event, data));
    }
  }

  Stream<T> on<T>(String event) {
    return eventStream
        .where((e) => e['type'] == event)
        .map((e) => e['data'] as T);
  }

  void disconnect() {
    _stopHeartbeat();
    _socket.disconnect();
  }

  void dispose() {
    _statusController.close();
    _eventController.close();
    disconnect();
  }
}
