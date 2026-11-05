import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:aqua_hatch/core/controller.dart';
import 'package:aqua_hatch/core/pairing.dart';
import 'package:aqua_hatch/core/models.dart';
import 'package:aqua_hatch/core/local_store.dart';
import 'package:aqua_hatch/core/credentials.dart';
import 'pairing_fixture.dart';

void main() {
  test(
    'controller refuses to save a camera as the main board or the reverse',
    () async {
      SharedPreferences.setMockInitialValues({});
      final store = LocalStore(await SharedPreferences.getInstance());
      final container = ProviderContainer(
        overrides: [localStoreProvider.overrideWithValue(store)],
      );
      addTearDown(container.dispose);
      final app = container.read(appControllerProvider.notifier);
      final s3 = PairingBundle.parse(jsonEncode(pairingFixture()));
      final camera = PairingBundle.parse(
        jsonEncode(pairingFixture(kind: 'camera')),
      );
      expect(
        await app.configure(camera.config('https://192.168.4.1'), camera.token),
        contains('กล้อง'),
      );
      expect(
        await app.configureCamera(s3.config('https://192.168.4.1'), s3.token),
        contains('บอร์ดหลัก'),
      );
      expect(store.pairedDevices, isEmpty);
    },
  );
  test(
    'different boards have separate public identities and secure credential keys',
    () {
      final first = PairingBundle.parse(jsonEncode(pairingFixture()));
      final second = PairingBundle.parse(
        jsonEncode(pairingFixture(mac: 'aabbccddee02')),
      );
      expect(first.identity.deviceId, isNot(second.identity.deviceId));
      expect(first.config('https://192.168.4.1').validate(), isNull);
      expect(first.identity.caPem, startsWith('-----BEGIN CERTIFICATE-----'));
      expect(first.toString(), isNot(contains(first.token)));
      const credentials = CredentialStore();
      expect(
        credentials.key(first.config('https://192.168.1.50')),
        credentials.key(first.config('https://192.168.1.99')),
      );
      expect(
        credentials.key(first.config('https://192.168.1.50')),
        isNot(credentials.key(second.config('https://192.168.1.50'))),
      );
    },
  );
  test(
    'QR parser rejects foreign payloads, incomplete identity and wrong device type',
    () {
      final cases = <Object?>[
        {},
        'https://example.com',
        {'format': 'aquahatch-pairing', 'version': 2},
        {...pairingFixture(), 'host': 'evil.example'},
        {...pairingFixture(), 'ssid': 'Other'},
        {...pairingFixture(), 'id': 'incubator-01'},
        {...pairingFixture(), 'token': 'guess'},
        {...pairingFixture(), 'ca': 'bogus'},
        {...pairingFixture(), 'url': 'https://example.com'},
      ];
      for (final payload in cases) {
        expect(
          () => PairingBundle.parse(jsonEncode(payload)),
          throwsFormatException,
        );
      }
      expect(
        () => PairingBundle.parse(
          jsonEncode(pairingFixture(kind: 'camera')),
          expectedKind: 's3',
        ),
        throwsFormatException,
      );
      expect(() => PairingBundle.parse('x' * 4097), throwsFormatException);
    },
  );
  test(
    'dynamic trust rejects mismatched ID and all external/plaintext/redirectable URLs',
    () {
      final bundle = PairingBundle.parse(jsonEncode(pairingFixture()));
      for (final url in [
        'http://192.168.1.20',
        'https://example.com',
        'https://127.0.0.1',
        'https://192.168.1.20:444',
        'https://192.168.1.20/path',
        'https://192.168.1.20?x=1',
      ]) {
        expect(bundle.config(url).validate(), isNotNull, reason: url);
      }
      expect(
        ConnectionConfig(
          demo: false,
          localEsp32: true,
          baseUrl: 'https://192.168.1.20',
          deviceId: 's3-aabbccddee02',
          identity: bundle.identity,
        ).validate(),
        isNotNull,
      );
    },
  );
  test(
    'paired registry survives app reload, retains multiple devices and never persists tokens',
    () async {
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      final store = LocalStore(preferences);
      final first = PairingBundle.parse(jsonEncode(pairingFixture()));
      final camera = PairingBundle.parse(
        jsonEncode(pairingFixture(kind: 'camera', mac: 'aabbccddee02')),
      );
      await store.rememberPairedDevice(first.config('https://192.168.1.20'));
      await store.rememberPairedDevice(camera.config('https://192.168.1.21'));
      await store.rememberPairedDevice(first.config('https://192.168.1.99'));
      final reload = LocalStore(preferences);
      expect(reload.pairedDevices.length, 2);
      expect(reload.pairedDevices.first.baseUrl, 'https://192.168.1.99');
      expect(
        preferences.getString('paired_devices_v1'),
        isNot(contains(first.token)),
      );
      expect(
        reload.scope(first.config('https://192.168.1.20')),
        reload.scope(first.config('https://192.168.1.99')),
      );
      expect(
        ConnectionConfig.fromJson(
          first.config('https://192.168.1.20').toJson(),
        ).identity!.fingerprint,
        first.identity.fingerprint,
      );
    },
  );
}
