import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class PhotoGallery {
  static const _channel = MethodChannel('th.ac.aquahatch/gallery');
  static final _captureFileName = RegExp(
    r'^AquaHatch_[A-Za-z0-9_-]{1,64}\.jpe?g$',
    caseSensitive: false,
  );

  static bool hasCaptureFileName(String name) =>
      _captureFileName.hasMatch(name);

  static bool get supported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  static bool isJpeg(Uint8List bytes) =>
      bytes.length >= 4 &&
      bytes[0] == 0xff &&
      bytes[1] == 0xd8 &&
      bytes[bytes.length - 2] == 0xff &&
      bytes.last == 0xd9;

  static Future<void> saveJpeg(String captureId, Uint8List bytes) =>
      _channel.invokeMethod<void>('saveJpeg', {
        'bytes': bytes,
        'name': 'AquaHatch_$captureId.jpg',
      });
}
