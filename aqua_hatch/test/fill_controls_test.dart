import 'package:aqua_hatch/core/controller.dart';
import 'package:aqua_hatch/core/models.dart';
import 'package:aqua_hatch/features/controls.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _Controller extends AppController {
  final bool viaRelay;
  _Controller(this.viaRelay);
  final commands = <(String, Map<String, dynamic>)>[];

  @override
  AppState build() {
    final now = DateTime.now();
    return AppState(
      connection: const ConnectionConfig(demo: false, localEsp32: true),
      settings: const DeviceSettings(),
      connected: true,
      now: now,
      telemetry: Telemetry(
        at: now,
        viaRelay: viaRelay,
        hardwareReady: false,
        fill: const FillStatus(
          armed: false,
          requested: true,
          running: false,
          timedOut: false,
          limitSeconds: 60,
        ),
      ),
    );
  }

  @override
  Future<String?> send(String action, Map<String, dynamic> payload) async {
    commands.add((action, payload));
    return null;
  }
}

void main() {
  for (final remote in [false, true]) {
    testWidgets(
      'fill controls are ${remote ? 'read-only remotely' : 'local and confirmed'}',
      (tester) async {
        tester.view.physicalSize = const Size(320, 620);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final controller = _Controller(remote);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [appControllerProvider.overrideWith(() => controller)],
            child: const MaterialApp(home: Scaffold(body: ControlsScreen())),
          ),
        );
        expect(find.text('ลูกลอยปิด · ขอเติมน้ำ'), findsOneWidget);
        expect(find.text('ฮีตเตอร์'), findsNothing);
        final start = find.widgetWithText(FilledButton, 'เปิดเติมน้ำอัตโนมัติ');
        expect(tester.widget<FilledButton>(start).onPressed == null, remote);
        if (!remote) {
          await tester.tap(start);
          await tester.pumpAndSettle();
          expect(controller.commands, isEmpty);
          await tester.tap(find.text('ยืนยันเปิด'));
          await tester.pumpAndSettle();
          expect(controller.commands.single.$1, 'set_fill');
          expect(controller.commands.single.$2, {'enabled': true});
        }
        expect(tester.takeException(), isNull);
      },
    );
  }
}
