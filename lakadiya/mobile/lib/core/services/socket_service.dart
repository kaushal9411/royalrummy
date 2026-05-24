import 'package:socket_io_client/socket_io_client.dart' as IO;
import '../constants/app_constants.dart';
import 'storage_service.dart';

typedef SocketCallback = void Function(dynamic data);

class SocketService {
  static final SocketService _instance = SocketService._internal();
  factory SocketService() => _instance;
  SocketService._internal();

  IO.Socket? _socket;
  bool get isConnected => _socket?.connected ?? false;

  void connect() {
    final token = StorageService.getToken();
    if (token == null) return;

    _socket = IO.io(
      AppConstants.socketUrl,
      IO.OptionBuilder()
          .setTransports(['websocket'])
          .setAuth({'token': token})
          .enableAutoConnect()
          .enableReconnection()
          .setReconnectionAttempts(5)
          .setReconnectionDelay(2000)
          .build(),
    );

    _socket!.onConnect((_) => _log('Connected'));
    _socket!.onDisconnect((_) => _log('Disconnected'));
    _socket!.onConnectError((e) => _log('Connect error: $e'));
    _socket!.connect();
  }

  void disconnect() => _socket?.disconnect();

  void emit(String event, [dynamic data]) => _socket?.emit(event, data);

  void on(String event, SocketCallback callback) =>
      _socket?.on(event, callback);

  void off(String event) => _socket?.off(event);

  void joinRoom(String roomId) => emit('join_room', {'roomId': roomId});

  void startGame(String roomId) => emit('start_game', {'roomId': roomId});

  void placeBid(String roomId, int bid) =>
      emit('place_bid', {'roomId': roomId, 'bid': bid});

  void playCard(String roomId, Map<String, String> card) =>
      emit('play_card', {'roomId': roomId, 'card': card});

  void nextRound(String roomId) => emit('next_round', {'roomId': roomId});

  void reconnect(String roomId) =>
      emit('reconnect_player', {'roomId': roomId});

  void sendChat(String roomId, String message) =>
      emit('chat_message', {'roomId': roomId, 'message': message});

  void sendEmoji(String roomId, String emoji) =>
      emit('send_emoji', {'roomId': roomId, 'emoji': emoji});

  void _log(String msg) {
    // ignore: avoid_print
    print('[Socket] $msg');
  }
}
