import 'dart:isolate';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'models.dart';
import 'repository.dart';

typedef FishHeadAnalyzer = Future<AnalysisResult> Function(Uint8List);

final fishHeadAnalyzerProvider = Provider<FishHeadAnalyzer?>((ref) {
  if (kIsWeb) return null;
  return switch (defaultTargetPlatform) {
    TargetPlatform.android ||
    TargetPlatform.iOS ||
    TargetPlatform.windows => _analyzeFishHeads,
    _ => null,
  };
});

const _largePhoto = (
  asset: 'assets/models/fishfry_heads_v1.onnx',
  id: 'aquahatch-fry-heads-v1',
  threshold: .34,
  radius: 3,
);
const _cameraPhoto = (
  asset: 'assets/models/fishfry_heads_v2.onnx',
  id: 'aquahatch-fry-heads-v2',
  threshold: 0.44,
  radius: 2,
);
const _side = 320;
const _halo = 32;
const _step = _side - 2 * _halo;
const _plane = _side * _side;

Future<AnalysisResult> _analyzeFishHeads(Uint8List bytes) async {
  final token = ui.RootIsolateToken.instance!;
  final pixels = await _decode(bytes);
  final profile = max(pixels.width, pixels.height) <= 2560
      ? _cameraPhoto
      : _largePhoto;
  try {
    final session = await OnnxRuntime().createSessionFromAsset(
      profile.asset,
      options: OrtSessionOptions(intraOpNumThreads: 3),
    );
    try {
      final points = await Isolate.run(
        () => _infer(pixels, session, token, profile.threshold, profile.radius),
      );
      return AnalysisResult(points, profile.id);
    } finally {
      await session.close();
    }
  } on PlatformException catch (error) {
    debugPrint('Fish head inference failed: $error');
    throw StateError('ประมวลผล AI ไม่สำเร็จ ลองอีกครั้งหรือเลือกนับด้วยมือ');
  }
}

Future<({int width, int height, TransferableTypedData rgba})> _decode(
  Uint8List bytes,
) async {
  final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
  try {
    final descriptor = await ui.ImageDescriptor.encoded(buffer);
    try {
      if (descriptor.width * descriptor.height > 20000000) {
        throw StateError('AI รองรับภาพขนาดไม่เกิน 20 ล้านพิกเซล');
      }
      final codec = await descriptor.instantiateCodec();
      try {
        final frame = await codec.getNextFrame();
        final image = frame.image;
        try {
          final rgba = await image.toByteData(
            format: ui.ImageByteFormat.rawStraightRgba,
          );
          if (rgba == null) throw StateError('อ่านพิกเซลของภาพไม่ได้');
          return (
            width: image.width,
            height: image.height,
            rgba: TransferableTypedData.fromList([
              rgba.buffer.asUint8List(rgba.offsetInBytes, rgba.lengthInBytes),
            ]),
          );
        } finally {
          image.dispose();
        }
      } finally {
        codec.dispose();
      }
    } finally {
      descriptor.dispose();
    }
  } finally {
    buffer.dispose();
  }
}

Future<List<CountPoint>> _infer(
  ({int width, int height, TransferableTypedData rgba}) pixels,
  OrtSession session,
  ui.RootIsolateToken token,
  double threshold,
  int radius,
) async {
  BackgroundIsolateBinaryMessenger.ensureInitialized(token);
  final width = pixels.width;
  final height = pixels.height;
  final rgba = pixels.rgba.materialize().asUint8List();
  final heatmap = Float32List(width * height);
  final rgb = Float32List(3 * _plane);
  final normalized = Float32List.fromList(
    List.generate(256, (value) => value / 127.5 - 1),
  );

  // Keep the interior of each overlapping tile. Find peaks after stitching
  // so a head at a tile boundary is only counted once.
  for (var top = 0; top < height; top += _step) {
    for (var left = 0; left < width; left += _step) {
      for (var y = 0; y < _side; y++) {
        final row = (top + y - _halo).clamp(0, height - 1) * width;
        for (var x = 0; x < _side; x++) {
          final index = y * _side + x;
          final source = (row + (left + x - _halo).clamp(0, width - 1)) * 4;
          rgb[index] = normalized[rgba[source]];
          rgb[index + _plane] = normalized[rgba[source + 1]];
          rgb[index + 2 * _plane] = normalized[rgba[source + 2]];
        }
      }

      final input = await OrtValue.fromList(rgb, [1, 3, _side, _side]);
      try {
        final outputs = await session.run({'rgb': input});
        try {
          final output = outputs['heatmap'];
          if (output == null ||
              !listEquals(output.shape, [1, 1, _side, _side])) {
            throw StateError('โมเดล AI ให้ผลลัพธ์ผิดรูปแบบ');
          }
          final values = (await output.asFlattenedList()).cast<double>();
          final copyWidth = min(_step, width - left);
          final copyHeight = min(_step, height - top);
          for (var y = 0; y < copyHeight; y++) {
            final destination = (top + y) * width + left;
            final source = (y + _halo) * _side + _halo;
            heatmap.setRange(
              destination,
              destination + copyWidth,
              values,
              source,
            );
          }
        } finally {
          for (final output in outputs.values) {
            await output.dispose();
          }
        }
      } finally {
        await input.dispose();
      }
    }
  }

  return _headPoints(heatmap, width, height, threshold, radius);
}

List<CountPoint> _headPoints(
  Float32List heatmap,
  int width,
  int height,
  double threshold,
  int radius,
) {
  final candidates = <int>[];
  for (var index = 0; index < heatmap.length; index++) {
    final score = heatmap[index];
    if (!score.isFinite || score < threshold) continue;
    final x = index % width;
    final y = index ~/ width;
    var peak = true;
    for (
      var row = max(0, y - radius);
      peak && row <= min(height - 1, y + radius);
      row++
    ) {
      for (
        var col = max(0, x - radius);
        col <= min(width - 1, x + radius);
        col++
      ) {
        if (heatmap[row * width + col] > score) {
          peak = false;
          break;
        }
      }
    }
    if (peak) candidates.add(index);
  }
  candidates.sort((a, b) {
    final byScore = heatmap[b].compareTo(heatmap[a]);
    return byScore != 0 ? byScore : a.compareTo(b);
  });

  // Equal-scoring pixels on one peak should produce one editable marker.
  final occupied = <int>{};
  final points = <CountPoint>[];
  for (final index in candidates) {
    final x = index % width;
    final y = index ~/ width;
    var duplicate = false;
    for (
      var row = max(0, y - radius);
      !duplicate && row <= min(height - 1, y + radius);
      row++
    ) {
      for (
        var col = max(0, x - radius);
        col <= min(width - 1, x + radius);
        col++
      ) {
        if (occupied.contains(row * width + col)) {
          duplicate = true;
          break;
        }
      }
    }
    if (duplicate) continue;
    occupied.add(index);
    points.add(CountPoint((x + .5) / width, (y + .5) / height));
  }
  return points;
}
