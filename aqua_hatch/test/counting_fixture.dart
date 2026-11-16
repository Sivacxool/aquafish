import 'package:aqua_hatch/core/models.dart';
import 'package:aqua_hatch/core/repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker_platform_interface/image_picker_platform_interface.dart';

import 'camera_widget_test.dart' show captured;

class _FixturePicker extends ImagePickerPlatform {
  @override
  Future<XFile?> getImageFromSource({
    required ImageSource source,
    ImagePickerOptions options = const ImagePickerOptions(),
  }) async => XFile.fromData(captured().bytes, name: 'fry.png');
}

Future<AnalysisResult> analyzeFixture(_) async =>
    AnalysisResult(samplePoints, 'fixture-heads');

Future<void> openFixtureWorkspace(WidgetTester tester) async {
  final original = ImagePickerPlatform.instance;
  ImagePickerPlatform.instance = _FixturePicker();
  addTearDown(() => ImagePickerPlatform.instance = original);
  final gallery = find.text('เลือกภาพ');
  await tester.ensureVisible(gallery);
  await tester.tap(gallery);
  await tester.pump();
  final analyze = find.widgetWithText(FilledButton, 'วิเคราะห์ด้วย AI');
  final watch = Stopwatch()..start();
  while (analyze.evaluate().isEmpty &&
      watch.elapsed < const Duration(seconds: 5)) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
  }
  expect(analyze, findsOneWidget);
  await tester.ensureVisible(analyze);
  await tester.tap(analyze);
  await tester.pumpAndSettle();
}
