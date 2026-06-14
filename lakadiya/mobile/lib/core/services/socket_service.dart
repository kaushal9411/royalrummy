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

  /// The token the live socket authenticated with. Lets us detect an account
  /// switch and rebuild the socket so it never acts as a previous user.
  String? _authedToken;

  /// The room this client should be a member of. Server-side room membership
  /// is per-connection and is dropped on every reconnect, so we re-join it on
  /// each (re)connect. Set via [joinRoom], cleared via [leaveCurrentRoom].
  String? _currentRoomId;
  String? get currentRoomId => _currentRoomId;

  void connect() {
    final token = StorageService.getToken();
    if (token == null) return;

    // Account switched (a new user logged in on this device): the existing
    // socket is still authenticated as the OLD user. Tear it down so we
    // reconnect with the current token. Without this the backend sees actions
    // (e.g. start_game) as the previous account → "Only host can start", etc.
    if (_socket != null && _authedToken != token) {
      reset();
    }

    if (_socket != null) {
      if (!_socket!.connected) _socket!.connect();
      return;
    }

    _authedToken = token;
    _socket = IO.io(
      AppConstants.socketUrl,
      IO.OptionBuilder()
          .setTransports(['websocket'])
          .setAuth({'token': token})
          .enableAutoConnect()
          .enableReconnection()
          .setReconnectionAttempts(999) // survive ngrok / network blips
          .setReconnectionDelay(1500)
          .build(),
    );

    _socket!.onConnect((_) {
      _log('Connected');
      // Re-join the active room on every (re)connect — membership is lost when
      // the underlying connection drops, which silently breaks io.to(room).
      final rid = _currentRoomId;
      if (rid != null) _socket!.emit('join_room', {'roomId': rid});
    });
    _socket!.onDisconnect((_) => _log('Disconnected'));
    _socket!.onConnectError((e) => _log('Connect error: $e'));
    _socket!.connect();
  }

  void disconnect() => _socket?.disconnect();

  /// Fully tears down the current socket and nulls the reference so that
  /// the next [connect] call creates a fresh socket with the current token.
  /// Must be called on logout BEFORE clearing storage.
  void reset() {
    _socket?.disconnect();
    _socket?.destroy();
    _socket = null;
    _authedToken   = null;
    _currentRoomId = null;
  }

  void emit(String event, [dynamic data]) => _socket?.emit(event, data);

  void on(String event, SocketCallback callback) =>
      _socket?.on(event, callback);

  void off(String event) => _socket?.off(event);

  /// Removes a specific listener. Always prefer this over [off] when multiple
  /// screens may register the same event (prevents removing other screens' callbacks).
  void offCallback(String event, SocketCallback callback) =>
      _socket?.off(event, callback);

  void joinRoom(String roomId) {
    _currentRoomId = roomId;
    emit('join_room', {'roomId': roomId});
  }

  /// Leaves the current room's socket channel (does NOT disconnect the shared
  /// socket — chat, notifications and lobby updates keep flowing).
  void leaveCurrentRoom() {
    final id = _currentRoomId;
    _currentRoomId = null;
    if (id != null) emit('leave_room', {'roomId': id});
  }

  void startGame(String roomId) => emit('start_game', {'roomId': roomId});

  /// Leave an active game mid-match — server notifies others + prompts the host
  /// to drop in a bot that resumes from this seat.
  void leaveGame(String roomId) => emit('leave_game', {'roomId': roomId});

  /// Host action: replace an abandoned seat with a medium bot.
  void replaceWithBot(String roomId, int seat) =>
      emit('replace_with_bot', {'roomId': roomId, 'seat': seat});

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

  /// Private, ephemeral in-game DM to a single player in the room.
  void sendGameDm(String roomId, String toUserId, String text) =>
      emit('game_dm', {'roomId': roomId, 'toUserId': toUserId, 'text': text});

  void sendPrivateMessage(String toUserId, String text) =>
      emit('private_message', {'toUserId': toUserId, 'text': text});

  void sendGameInvite(String toUserId, String roomId, String roomCode) =>
      emit('send_game_invite', {'toUserId': toUserId, 'roomId': roomId, 'roomCode': roomCode});

  void _log(String msg) {
    // ignore: avoid_print
    print('[Socket] $msg');
  }
}
