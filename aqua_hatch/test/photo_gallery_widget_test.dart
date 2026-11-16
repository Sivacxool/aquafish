import 'dart:async';
import 'dart:convert';

import 'package:aqua_hatch/core/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'camera_widget_test.dart' as fixture;

const _channel = MethodChannel('th.ac.aquahatch/gallery');
const _saveButton = ValueKey('save-photo-to-gallery');
final _jpeg = base64Decode(
  '/9j/4AAQSkZJRgABAQAAAQABAAD/2wBDAAYEBQYFBAYGBQYHBwYIChAKCgkJChQODwwQFxQYGBcUFhYaHSUfGhsjHBYWICwgIyYnKSopGR8tMC0oMCUoKSj/2wBDAQcHBwoIChMKChMoGhYaKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCgoKCj/wAARCAAGAAgDASIAAhEBAxEB/8QAFQABAQAAAAAAAAAAAAAAAAAAAAf/xAAUEAEAAAAAAAAAAAAAAAAAAAAA/8QAFQEBAQAAAAAAAAAAAAAAAAAABAX/xAAUEQEAAAAAAAAAAAAAAAAAAAAA/9oADAMBAAIRAxEAPwCaAHo7/9k=',
);

void main() {
  testWidgets(
    'saves the original capture on request and keeps the retry action after denial',
    variant: TargetPlatformVariant({
      TargetPlatform.android,
      TargetPlatform.iOS,
    }),
    (tester) async {
      final app = fixture.CameraController();
      final calls = <MethodCall>[];
      final permission = Completer<void>();
      var rejected = true;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_channel, (call) async {
            calls.add(call);
            if (rejected) {
              throw PlatformException(code: 'permission_denied');
            }
            await permission.future;
            return null;
          });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(_channel, null);
      });

      await fixture.mount(tester, app);
      expect(find.byKey(_saveButton), findsNothing);
      await tester.tap(find.byKey(const ValueKey('device-capture-button')));
      await tester.pump();
      app.photo.complete(
        DeviceCapture(
          id: 'fry-photo-1',
          cameraId: 'cam-ett',
          sensor: 'Arducam B0434',
          receivedAt: DateTime(2026, 11, 16),
          bytes: _jpeg,
          width: 8,
          height: 6,
        ),
      );
      final wait = Stopwatch()..start();
      while (find.byKey(_saveButton).evaluate().isEmpty &&
          wait.elapsed < const Duration(seconds: 5)) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 10)),
        );
        await tester.pump();
      }

      final button = find.byKey(_saveButton);
      expect(button, findsOneWidget);
      expect(calls, isEmpty);
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pumpAndSettle();
      expect(
        find.textContaining('อนุญาตให้ AquaHatch เพิ่มรูป'),
        findsOneWidget,
      );
      expect(tester.widget<TextButton>(button).onPressed, isNotNull);

      rejected = false;
      await tester.tap(button);
      await tester.pump();
      expect(tester.widget<TextButton>(button).onPressed, isNull);
      expect(calls, hasLength(2));
      expect(calls.last.method, 'saveJpeg');
      expect(calls.last.arguments, {
        'bytes': orderedEquals(_jpeg),
        'name': 'AquaHatch_fry-photo-1.jpg',
      });
      permission.complete();
      await tester.pumpAndSettle();
      expect(find.text('บันทึกรูปแล้ว'), findsOneWidget);
      expect(tester.widget<TextButton>(button).onPressed, isNull);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
