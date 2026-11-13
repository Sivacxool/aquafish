import 'package:aqua_hatch/core/controller.dart';
import 'package:aqua_hatch/core/models.dart';
import 'package:aqua_hatch/features/controls.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _EttRelayController extends AppController {
  _EttRelayController({required this.remote});
  final bool remote;
  final commands = <(String, Map<String, dynamic>)>[];
  late final DateTime _start;

  Telemetry reading({bool manual = false, bool fan = false}) => Telemetry(
    at: _start,
    temperature: 29,
    viaRelay: remote,
    hardwareReady: !remote,
    mode: manual ? RunMode.manual : RunMode.automatic,
    manualUntil: manual ? _start.add(const Duration(minutes: 5)) : null,
    ettControl: EttControlStatus(ioReady: true, fanCommandedOn: fan),
    fill: const FillStatus(
      armed: false,
      requested: true,
      running: false,
      timedOut: false,
      limitSeconds: 60,
    ),
    heater: const HeaterStatus(ready: true, commandedOn: false),
  );

  @override
  AppState build() {
    _start = DateTime.now();
    return AppState(
      connection: const ConnectionConfig(demo: false, localEsp32: true),
      settings: const DeviceSettings(),
      connected: true,
      now: _start,
      telemetry: reading(manual: remote, fan: remote),
    );
  }

  @override
  Future<String?> send(String action, Map<String, dynamic> payload) async {
    commands.add((action, payload));
    if (action == 'set_mode') {
      state = state.copyWith(
        telemetry: reading(manual: payload['mode'] == 'manual'),
      );
    } else if (payload['output'] == 'cooler') {
      state = state.copyWith(
        telemetry: reading(manual: true, fan: payload['enabled'] == true),
      );
    }
    return null;
  }

  void expire() {
    state = state.copyWith(now: _start.add(const Duration(minutes: 5)));
  }
}

void main() {
  for (final remote in [false, true]) {
    testWidgets(
      'ETT manual controls respect confirmed mode and LAN access (remote=$remote)',
      (tester) async {
        tester.view.physicalSize = const Size(320, 620);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final controller = _EttRelayController(remote: remote);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [appControllerProvider.overrideWith(() => controller)],
            child: const MaterialApp(home: Scaffold(body: ControlsScreen())),
          ),
        );
        final mode = find.byType(SegmentedButton<bool>);
        final fan = find.byKey(const ValueKey('manual-output-cooler'));
        expect(
          tester.widget<SegmentedButton<bool>>(mode).onSelectionChanged == null,
          remote,
        );
        expect(find.text('RY2'), findsOneWidget);
        if (remote) {
          expect(tester.widget<Switch>(fan).value, isTrue);
          expect(tester.widget<Switch>(fan).onChanged, isNull);
          expect(controller.commands, isEmpty);
        } else {
          expect(fan, findsNothing);
          await tester.tap(find.text('Manual 5 นาที'));
          await tester.pumpAndSettle();
          expect(controller.commands, isEmpty);
          await tester.tap(find.text('เริ่มควบคุม'));
          await tester.pumpAndSettle();
          expect(controller.commands.single.$1, 'set_mode');
          expect(controller.commands.single.$2, {
            'mode': 'manual',
            'duration_seconds': 300,
          });
          expect(find.text('5:00'), findsOneWidget);
          expect(
            find.byKey(const ValueKey('manual-output-heater')),
            findsOneWidget,
          );
          expect(
            find.byKey(const ValueKey('manual-output-pump')),
            findsOneWidget,
          );
          await tester.ensureVisible(fan);
          await tester.tap(fan);
          await tester.pumpAndSettle();
          expect(controller.commands.last.$1, 'set_output');
          expect(controller.commands.last.$2, {
            'output': 'cooler',
            'enabled': true,
          });
          expect(tester.widget<Switch>(fan).value, isTrue);
          controller.expire();
          await tester.pumpAndSettle();
          expect(fan, findsNothing);
          expect(tester.widget<SegmentedButton<bool>>(mode).selected, {false});
        }
        expect(tester.takeException(), isNull);
      },
    );
  }
}
