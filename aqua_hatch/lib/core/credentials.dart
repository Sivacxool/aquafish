import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'models.dart';

class CredentialStore {
  final FlutterSecureStorage storage;
  const CredentialStore({this.storage = const FlutterSecureStorage()});
  String key(ConnectionConfig config) =>
      '${config.localEsp32 ? 'esp32' : 'gateway'}:${config.baseUrl.replaceAll(RegExp(r'/+$'), '')}:${config.deviceId}';
  Future<String> read(ConnectionConfig config) async =>
      kIsWeb ? '' : await storage.read(key: key(config)) ?? '';
  Future<void> save(ConnectionConfig config, String token) async {
    if (!kIsWeb) await storage.write(key: key(config), value: token);
  }

  Future<void> forget(ConnectionConfig config) async {
    if (!kIsWeb) await storage.delete(key: key(config));
  }
}
