import 'dart:convert';

import 'package:aqua_hatch/app/app.dart';
import 'package:aqua_hatch/core/controller.dart';
import 'package:aqua_hatch/core/models.dart';
import 'package:aqua_hatch/core/local_store.dart';
import 'package:aqua_hatch/core/ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class NotificationController extends AppController {
  @override
  AppState build() => AppState(
    connection: const ConnectionConfig(),
    settings: const DeviceSettings(),
    now: DateTime.now(),
    events: List.generate(30, (index) => DeviceEvent('กิจกรรม $index')),
  );
}

void main() {
  testWidgets(
    'close stays visible after scrolling and dismisses notifications',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appControllerProvider.overrideWith(NotificationController.new),
          ],
          child: const AquaHatchApp(),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('กิจกรรมและการแจ้งเตือน'));
      await tester.pumpAndSettle();

      final close = find.byTooltip('ปิดการแจ้งเตือน');
      final header = tester.getCenter(close);
      await tester.drag(
        find.byKey(const ValueKey('notification-events')),
        const Offset(0, -720),
      );
      await tester.pumpAndSettle();
      expect(tester.getCenter(close), header);
      await tester.tap(close);
      await tester.pumpAndSettle();
      expect(close, findsNothing);
      expect(find.byTooltip('กิจกรรมและการแจ้งเตือน'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('clearing notifications updates the open sheet and persists', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'events_v2:demo': jsonEncode([
        DeviceEvent('แจ้งเตือนเก่า', warning: true).toJson(),
      ]),
    });
    final store = LocalStore(await SharedPreferences.getInstance());
    await tester.pumpWidget(
      ProviderScope(
        overrides: [localStoreProvider.overrideWithValue(store)],
        child: const AquaHatchApp(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('กิจกรรมและการแจ้งเตือน'));
    await tester.pumpAndSettle();
    expect(find.text('แจ้งเตือนเก่า'), findsOneWidget);
    await tester.tap(find.text('ล้างการแจ้งเตือน'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'ล้าง'));
    await tester.pumpAndSettle();
    expect(find.text('ยังไม่มีกิจกรรม'), findsOneWidget);
    expect(store.events(store.connection), isEmpty);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });

  testWidgets('only the newest feedback remains after rapid actions', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              return TextButton(
                onPressed: () {
                  showFeedback(context, 'ข้อความเก่า');
                  showFeedback(context, 'ข้อความล่าสุด');
                },
                child: const Text('ส่งคำสั่ง'),
              );
            },
          ),
        ),
      ),
    );
    await tester.tap(find.text('ส่งคำสั่ง'));
    await tester.pumpAndSettle();
    expect(find.text('ข้อความเก่า'), findsNothing);
    expect(find.text('ข้อความล่าสุด'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(find.byType(SnackBar), findsNothing);
  });
}
