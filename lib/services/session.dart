import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

import '../models.dart';
import 'api.dart';
import 'notifications.dart';

/// A change pushed by the server over Socket.io.
class LiveEvent {
  final String name;
  final dynamic data;
  LiveEvent(this.name, this.data);
}

/// App-wide state: who is signed in, the API client and the live socket.
class Session extends ChangeNotifier {
  static const _kToken = 'token';
  static const _kServer = 'serverUrl';
  static const _kBiometric = 'biometricLock';

  final api = ApiClient(baseUrl: ApiClient.defaultBaseUrl);
  final _auth = LocalAuthentication();
  final _events = StreamController<LiveEvent>.broadcast();

  AppUser? user;
  bool ready = false;
  bool locked = false;
  bool biometricLock = false;
  bool live = false;
  io.Socket? _socket;

  /// Screens listen to this to refresh when web or another phone changes data.
  Stream<LiveEvent> get events => _events.stream;
  bool get signedIn => user != null;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    api.baseUrl = prefs.getString(_kServer) ?? api.baseUrl;
    api.token = prefs.getString(_kToken);
    biometricLock = prefs.getBool(_kBiometric) ?? false;
    if (api.token != null) {
      try {
        final res = await api.get('/auth/me');
        user = AppUser.fromJson(res['user']);
        locked = biometricLock;
        _connectSocket();
      } on ApiException catch (e) {
        // Keep the token if the server is just unreachable; drop it if rejected.
        if (e.status == 401) await _clearToken();
      }
    }
    ready = true;
    notifyListeners();
  }

  Future<void> setServerUrl(String url) async {
    api.baseUrl = url.trim();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kServer, api.baseUrl);
    if (signedIn) _connectSocket();
    notifyListeners();
  }

  Future<void> login(String email, String password) async {
    final res = await api.post('/auth/login', {'email': email.trim(), 'password': password});
    await _signedIn(res);
  }

  Future<void> register(String name, String email, String password) async {
    final res = await api.post('/auth/register', {'name': name.trim(), 'email': email.trim(), 'password': password});
    await _signedIn(res);
  }

  Future<void> _signedIn(dynamic res) async {
    api.token = res['token'];
    user = AppUser.fromJson(res['user']);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kToken, api.token!);
    _connectSocket();
    notifyListeners();
  }

  Future<void> updateProfile(Map<String, dynamic> changes) async {
    final res = await api.patch('/auth/me', changes);
    user = AppUser.fromJson(res['user']);
    notifyListeners();
  }

  Future<void> logout() async {
    _socket?.dispose();
    _socket = null;
    live = false;
    user = null;
    locked = false;
    await _clearToken();
    notifyListeners();
  }

  Future<void> _clearToken() async {
    api.token = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kToken);
  }

  // ---------- Biometric lock ----------

  Future<bool> biometricsAvailable() async {
    try {
      return await _auth.isDeviceSupported() && await _auth.canCheckBiometrics;
    } catch (_) {
      return false;
    }
  }

  Future<bool> setBiometricLock(bool enabled) async {
    if (enabled && !await _authenticate('Confirm to enable biometric unlock')) return false;
    biometricLock = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kBiometric, enabled);
    notifyListeners();
    return true;
  }

  Future<void> unlock() async {
    if (await _authenticate('Unlock TeamFlow')) {
      locked = false;
      notifyListeners();
    }
  }

  Future<bool> _authenticate(String reason) async {
    try {
      return await _auth.authenticate(localizedReason: reason, persistAcrossBackgrounding: true);
    } catch (e) {
      debugPrint('Biometric auth failed: $e');
      return false;
    }
  }

  // ---------- Real-time ----------

  void _connectSocket() {
    _socket?.dispose();
    final socket = io.io(
      api.baseUrl,
      io.OptionBuilder().setTransports(['websocket']).setAuth({'token': api.token}).enableReconnection().disableAutoConnect().build(),
    );
    socket.onConnect((_) {
      live = true;
      notifyListeners();
    });
    socket.onDisconnect((_) {
      live = false;
      notifyListeners();
    });
    for (final name in ['task:created', 'task:updated', 'task:deleted', 'tasks:refresh', 'project:changed', 'team:updated', 'activity:new']) {
      socket.on(name, (data) => _events.add(LiveEvent(name, data)));
    }
    socket.on('notify', (data) {
      if (data is Map) Notifications.show('${data['title']}', '${data['body']}');
      _events.add(LiveEvent('notify', data));
    });
    socket.connect();
    _socket = socket;
  }

  void subscribeTeam(String teamId) => _socket?.emit('team:subscribe', teamId);

  @override
  void dispose() {
    _socket?.dispose();
    _events.close();
    super.dispose();
  }
}

final session = Session();
