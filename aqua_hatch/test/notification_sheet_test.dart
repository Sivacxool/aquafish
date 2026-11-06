import 'package:aqua_hatch/app/app.dart';
import 'package:aqua_hatch/core/controller.dart';
import 'package:aqua_hatch/core/models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

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
}
