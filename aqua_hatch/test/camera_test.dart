import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:aqua_hatch/core/live_repository.dart';
import 'package:aqua_hatch/core/models.dart';

void main() {
  const config = ConnectionConfig(
    demo: false,
    baseUrl: 'https://cloud.example',
  );
  test(
    'capture polls one job, downloads its image, then analyzes saved capture',
    () async {
      final calls = <String>[];
      final repo = LiveRepository(
        config,
        'test-token',
        client: MockClient((request) async {
          calls.add('${request.method} ${request.url.path}');
          expect(request.headers['Authorization'], 'Bearer test-token');
          if (request.url.path.endsWith('/image')) {
            return http.Response.bytes(
              [255, 216, 255, 217],
              200,
              headers: {'content-type': 'image/jpeg'},
            );
          }
          if (request.url.path.endsWith('/analyze')) {
            return http.Response(
              jsonEncode({
                'model_version': 'test-model',
                'points': [
                  {'x': .3, 'y': .2},
                ],
              }),
              200,
            );
          }
          final creating = request.method == 'POST';
          if (creating) {
            expect(jsonDecode(request.body)['capture_id'], 'photo-1');
          }
          return http.Response(
            jsonEncode({
              'capture_id': 'photo-1',
              'camera_id': 'cam-1',
              'status': creating ? 'queued' : 'captured',
              'received_at': '2026-10-19T15:00:00Z',
            }),
            creating ? 202 : 200,
          );
        }),
      );
      addTearDown(repo.dispose);
      final progress = <String>[];
      final image = await repo.capture('photo-1', onProgress: progress.add);
      expect(image.id, 'photo-1');
      expect(image.cameraId, 'cam-1');
      expect(image.bytes.length, 4);
      expect(progress.length, greaterThan(1));
      expect(calls.where((call) => call.startsWith('POST')).length, 1);
      final analysis = await repo.analyzeCapture(image.id);
      expect(analysis.points.length, 1);
      expect(calls.last, endsWith('/camera/captures/photo-1/analyze'));
    },
  );

  test(
    'expired capture, mismatched ID, and missing AI fail without fake results',
    () async {
      for (final job in [
        {'capture_id': 'photo-1', 'status': 'expired', 'message': 'หมดเวลา'},
        {'capture_id': 'different', 'status': 'captured'},
      ]) {
        final repo = LiveRepository(
          config,
          'token',
          client: MockClient(
            (_) async => http.Response(
              jsonEncode(job),
              202,
              headers: {'content-type': 'application/json; charset=utf-8'},
            ),
          ),
        );
        await expectLater(repo.capture('photo-1'), throwsStateError);
        await repo.dispose();
      }
      final repo = LiveRepository(
        config,
        'token',
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({'detail': 'ยังไม่มีโมเดล'}),
            503,
            headers: {'content-type': 'application/json; charset=utf-8'},
          ),
        ),
      );
      addTearDown(repo.dispose);
      await expectLater(repo.analyzeCapture('photo-1'), throwsStateError);
    },
  );

  test('cancel before sending does not command camera', () async {
    var called = false;
    final repo = LiveRepository(
      config,
      'token',
      client: MockClient((_) async {
        called = true;
        return http.Response('', 500);
      }),
    );
    addTearDown(repo.dispose);
    await expectLater(
      repo.capture('photo-1', cancelled: () => true),
      throwsStateError,
    );
    expect(called, isFalse);
  });
}
