import 'package:flutter/services.dart';

class WifiPlatform {
  static const _channel = MethodChannel('th.ac.aquahatch/wifi');
  const WifiPlatform();
  Future<void> openSettings() async {
    await _channel.invokeMethod<void>('openWifiSettings');
  }

  Future<void> bindWifi() async {
    await _channel.invokeMethod<bool>('bindWifi');
  }

  Future<void> releaseWifi() async {
    await _channel.invokeMethod<bool>('releaseWifi');
  }
}
