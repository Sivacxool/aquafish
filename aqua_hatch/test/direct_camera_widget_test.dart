import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aqua_hatch/core/controller.dart';
import 'package:aqua_hatch/core/models.dart';
import 'camera_widget_test.dart' as camera_fixture;
import 'direct_camera_test.dart' as network_fixture;

class IndependentCamera extends camera_fixture.CameraController {
  @override
  AppState build() => AppState(
    connection: const ConnectionConfig(),
    cameraConnection: network_fixture.config,
    settings: const DeviceSettings(),
    now: DateTime.now(),
  );
}

void main() {
  testWidgets(
    'a saved ESP32-CAM cannot expose capture before the ETT is paired',
    (tester) async {
      final app = IndependentCamera();
      await camera_fixture.mount(tester, app);
      expect(find.text('เชื่อมบอร์ด ETT'), findsOneWidget);
      expect(find.text('ESP32-CAM'), findsNothing);
      expect(find.text('เพิ่มกล้อง'), findsNothing);
      final shutter = find.byKey(const ValueKey('device-capture-button'));
      expect(tester.widget<OutlinedButton>(shutter).onPressed, isNull);
      expect(app.captures, 0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
