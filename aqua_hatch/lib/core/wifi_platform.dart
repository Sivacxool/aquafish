import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class WifiPlatform {
  static const _channel = MethodChannel('th.ac.aquahatch/wifi');
  const WifiPlatform();
  bool get requiresManualWifiSelection =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  Future<void> openSettings() async {
    // iOS has no public URL for opening the Wi-Fi picker. The setup screen
    // presents instructions instead of using an undocumented Settings URL.
    if (requiresManualWifiSelection) return;
    await _channel.invokeMethod<void>('openWifiSettings');
  }

  Future<void> bindWifi() async {
    // Android binds the process to Wi-Fi during SoftAP setup. On iOS, routing
    // follows the network selected by the user in Settings.
    if (requiresManualWifiSelection) return;
    await _channel.invokeMethod<bool>('bindWifi');
  }

  Future<void> releaseWifi() async {
    if (requiresManualWifiSelection) return;
    await _channel.invokeMethod<bool>('releaseWifi');
  }
}
