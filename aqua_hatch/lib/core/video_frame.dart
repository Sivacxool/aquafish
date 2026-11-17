import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class VideoFrame {
  static const _channel = MethodChannel('th.ac.aquahatch/video_frame');

  static bool get supported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  static Future<Uint8List> read(String path) async {
    final bytes = await _channel.invokeMethod<Uint8List>('read', path);
    if (bytes == null || bytes.isEmpty) {
      throw StateError('อ่านเฟรมจากคลิปไม่ได้');
    }
    return bytes;
  }
}
