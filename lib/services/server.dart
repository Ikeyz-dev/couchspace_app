import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

/// Optional: hard-code your backend here so the app works with no setup.
/// Example: 'https://couchspace.onrender.com'
const String kDefaultServerUrl = '';

enum ConnState { idle, connecting, connected, disconnected }

class Server extends ChangeNotifier {
  Server._();
  static final Server I = Server._();

  String url = '';
  String displayName = '';
  io.Socket? socket;
  ConnState state = ConnState.idle;
  String? lastError;
  SharedPreferences? _prefs;

  bool get connected => state == ConnState.connected;
  bool get hasUrl => url.isNotEmpty;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    url = _prefs!.getString('server_url') ?? kDefaultServerUrl;
    displayName = _prefs!.getString('display_name') ?? '';
    if (url.isNotEmpty) connect();
  }

  static String normalize(String raw) {
    var s = raw.trim();
    if (s.isEmpty) return '';
    if (!s.startsWith('http://') && !s.startsWith('https://')) s = 'https://$s';
    try {
      final u = Uri.parse(s);
      if (u.host.isEmpty) return '';
      return '${u.scheme}://${u.authority}';
    } catch (_) {
      return '';
    }
  }

  Future<void> setUrl(String raw) async {
    url = normalize(raw);
    await _prefs?.setString('server_url', url);
    connect();
  }

  Future<void> setDisplayName(String name) async {
    displayName = name;
    await _prefs?.setString('display_name', name);
  }

  void _teardown() {
    final s = socket;
    socket = null;
    if (s != null) {
      s.disconnect();
      s.dispose();
    }
  }

  void connect() {
    _teardown();
    if (url.isEmpty) {
      state = ConnState.idle;
      notifyListeners();
      return;
    }
    state = ConnState.connecting;
    lastError = null;
    notifyListeners();

    final s = io.io(url, <String, dynamic>{
      'transports': ['websocket'],
      'autoConnect': false,
      'reconnection': true,
      'reconnectionDelay': 1000,
      'reconnectionDelayMax': 5000,
      'timeout': 20000,
    });
    socket = s;
    s.onConnect((_) {
      state = ConnState.connected;
      lastError = null;
      notifyListeners();
    });
    s.onDisconnect((_) {
      state = ConnState.disconnected;
      notifyListeners();
    });
    s.onConnectError((e) {
      state = ConnState.connecting;
      lastError = '$e';
      notifyListeners();
    });
    s.connect();
  }

  /// Emit an event with an acknowledgement callback (like the web client does).
  Future<dynamic> ask(String event, [dynamic data]) {
    final s = socket;
    if (s == null || !s.connected) {
      return Future.error('Not connected to the server');
    }
    final c = Completer<dynamic>();
    s.emitWithAck(event, data, ack: ([dynamic a, dynamic b]) {
      if (!c.isCompleted) c.complete(a);
    });
    return c.future.timeout(const Duration(seconds: 15),
        onTimeout: () => throw TimeoutException('The server did not respond'));
  }

  void emit(String event, [dynamic data]) {
    socket?.emit(event, data);
  }

  /// Waits for the socket to connect (Render free tier can take ~50s to wake).
  Future<bool> waitConnected({Duration timeout = const Duration(seconds: 75)}) async {
    if (connected) return true;
    if (!hasUrl) return false;
    final c = Completer<bool>();
    void listener() {
      if (connected && !c.isCompleted) c.complete(true);
    }

    addListener(listener);
    final t = Timer(timeout, () {
      if (!c.isCompleted) c.complete(false);
    });
    final ok = await c.future;
    removeListener(listener);
    t.cancel();
    return ok;
  }

  /// Leaves the current room server-side (same trick as the web client).
  void leaveRoom() {
    final s = socket;
    if (s == null) return;
    s.disconnect();
    s.connect();
  }

  static String friendlyError(Object e) {
    final m = '$e';
    if (m.contains('TimeoutException')) return 'The server took too long to respond. Try again.';
    if (m.contains('Not connected')) return 'Not connected to the server yet.';
    return m.replaceFirst('Exception: ', '');
  }
}
