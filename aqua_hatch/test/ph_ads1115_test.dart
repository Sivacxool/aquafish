import 'package:flutter_test/flutter_test.dart';
import 'package:aqua_hatch/core/models.dart';
import 'package:aqua_hatch/features/history.dart';

void main() {
  test(
    'pH failures never turn a fresh HTTP packet into a valid measurement',
    () {
      for (final status in [
        'adc_not_found',
        'stale',
        'not_calibrated',
        'input_out_of_range',
        'read_error',
      ]) {
        final reading = Telemetry.fromJson({
          'timestamp': DateTime.now().toIso8601String(),
          'ph': 7.1,
          'ph_status': status,
          'ph_calibrated': false,
          'ph_adc_voltage': 1.25,
          'ph_calibration': {'neutral_voltage': 1.25, 'neutral_ph': 6.86},
        });
        expect(reading.ph, isNull);
        expect(reading.phSensor.supported, isTrue);
        expect(reading.phSensor.neutralPh, 6.86);
      }
    },
  );
  test(
    'calibration, voltage and pH diagnostics survive history serialization',
    () {
      final reading = Telemetry.fromJson({
        'timestamp': DateTime.now().toIso8601String(),
        'ph': 7.1,
        'ph_status': 'ok',
        'ph_calibrated': true,
        'ph_adc_voltage': 1.242,
        'ph_stable': true,
        'ph_sampled_at': '2026-11-05T08:00:00Z',
        'ph_calibration': {
          'neutral_voltage': 1.25,
          'acid_voltage': 1.50,
          'neutral_ph': 7,
          'acid_ph': 4,
        },
      });
      final restored = Telemetry.fromJson(reading.toJson());
      expect(restored.ph, 7.1);
      expect(restored.phSensor.adcVoltage, 1.242);
      expect(restored.phSensor.acidVoltage, 1.50);
      expect(restored.phSensor.stable, isTrue);
      expect(telemetryCsv([restored]), isNot(contains('flow_l_min')));
    },
  );
  test(
    'legacy saved flow fields are ignored and are not sent or warned about',
    () {
      final settings = DeviceSettings.fromJson({
        'temperature_target': 28,
        'ph_minimum': 6.5,
        'ph_maximum': 8.5,
        'flow_target': -1,
      });
      expect(settings.validate(), isNull);
      expect(
        settings.toJson().keys,
        unorderedEquals(['temperature_target', 'ph_minimum', 'ph_maximum']),
      );
      final t = Telemetry.fromJson({
        'timestamp': DateTime.now().toIso8601String(),
        'flow_l_min': null,
      });
      expect(t.toJson().containsKey('flow_l_min'), isFalse);
      expect(t.alerts(settings).any((s) => s.contains('ไหล')), isFalse);
    },
  );
}
