import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../app/theme.dart';
import '../core/board_wifi.dart';
import '../core/controller.dart';
import '../core/models.dart';
import '../core/wifi_platform.dart';
import '../core/paired_camera.dart';
import 'connection_journey.dart';

class WifiSetupScreen extends ConsumerStatefulWidget {
  final WifiPlatform platform;
  final bool camera;
  final BoardWifiClient Function(ConnectionConfig, String)? clientFactory;
  const WifiSetupScreen({
    super.key,
    this.platform = const WifiPlatform(),
    this.camera = false,
    this.clientFactory,
  });
  @override
  ConsumerState<WifiSetupScreen> createState() => _WifiSetupScreenState();
}

class _WifiSetupScreenState extends ConsumerState<WifiSetupScreen> {
  final _pairing = TextEditingController(),
      _password = TextEditingController(),
      _hiddenName = TextEditingController();
  late final AppController _app;
  late final ConnectionConfig _initial;
  late final Future<void> _initializing;
  BoardWifiClient? _client;
  BoardWifiStatus? _status;
  String _savedToken = '',
      _token = '',
      _selected = '',
      _requestId = '',
      _target = '',
      _lanIp = '';
  String? _error;
  bool _busy = false,
      _loaded = false,
      _reuse = false,
      _hidden = false,
      _showApPassword = false,
      _completed = false;
  int _stage = 0;
  final _scroll = ScrollController();
  bool _showPassword = false, _showPairing = false;

  @override
  void initState() {
    super.initState();
    _app = ref.read(appControllerProvider.notifier);
    final state = ref.read(appControllerProvider);
    _initial = widget.camera
        ? state.cameraConnection ??
              const ConnectionConfig(
                demo: false,
                localEsp32: true,
                baseUrl: setupBoardUrl,
                deviceId: cameraDeviceId,
              )
        : state.connection;
    _initializing = _initialize();
  }

  Future<void> _initialize() async {
    await _app.pauseForWifiSetup();
    if (!mounted) return;
    try {
      if (_initial.localEsp32) {
        _savedToken = await ref.read(credentialStoreProvider).read(_initial);
      }
    } catch (_) {
      /* The pairing card can be entered instead. */
    }
    if (mounted) setState(() => _loaded = true);
  }

  @override
  void dispose() {
    _client?.close();
    _scroll.dispose();
    _pairing.dispose();
    _password.dispose();
    _hiddenName.dispose();
    unawaited(() async {
      await _initializing;
      try {
        await widget.platform.releaseWifi();
      } catch (_) {
        /* Android may be shutting down. */
      }
      if (!_completed) await _app.reconnect();
    }());
    super.dispose();
  }

  ConnectionConfig _config(String url) => ConnectionConfig(
    demo: false,
    localEsp32: true,
    baseUrl: url,
    deviceId: _initial.deviceId,
  );
  BoardWifiClient _make(String url) =>
      widget.clientFactory?.call(_config(url), _token) ??
      (widget.camera
          ? BoardWifiClient(
              _config(url),
              _token,
              hostname: cameraTlsHostname,
              caAsset: cameraCaAsset,
            )
          : BoardWifiClient(_config(url), _token));
  void _replace(BoardWifiClient client) {
    _client?.close();
    _client = client;
  }

  String _friendly(Object error) {
    final text = error.toString();
    if (text.contains('CERTIFICATE_VERIFY_FAILED')) {
      return 'ใบรับรองไม่ตรงกับบอร์ดที่จับคู่ ตรวจว่าใช้แอปรุ่นที่มากับเครื่อง';
    }
    if (text.contains('TimeoutException') ||
        text.contains('SocketException') ||
        text.contains('ClientException')) {
      return 'ยังติดต่อบอร์ดไม่ได้ ตรวจ Wi-Fi ที่เชื่อมอยู่ แล้วลองอีกครั้ง';
    }
    if (error is MissingPluginException) {
      return 'เปิดหน้าตั้งค่า Wi-Fi ของเครื่องด้วยตนเอง แล้วกลับมาที่แอป';
    }
    return text.replaceFirst(RegExp(r'^(Bad state: |Exception: )'), '');
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    FocusManager.instance.primaryFocus?.unfocus();
    final previousStage = _stage;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (error) {
      if (mounted) setState(() => _error = _friendly(error));
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        if (_stage != previousStage || _error != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _scroll.hasClients) {
              _scroll.animateTo(
                0,
                duration: const Duration(milliseconds: 280),
                curve: Curves.easeOutCubic,
              );
            }
          });
        }
      }
    }
  }

  Future<void> _openSettings() async {
    try {
      await widget.platform.openSettings();
    } catch (error) {
      if (mounted) setState(() => _error = _friendly(error));
    }
  }

  Future<void> _bind() async {
    try {
      await widget.platform.bindWifi();
    } on MissingPluginException {
      /* Unit tests and unsupported platforms. */
    }
  }

  Future<void> _start() => _run(() async {
    _token = _pairing.text.trim().isEmpty ? _savedToken : _pairing.text.trim();
    if (_token.isEmpty) {
      throw StateError('ใส่รหัสจับคู่จากบัตรประจำเครื่องก่อน');
    }
    await _bind();
    if (_initial.localEsp32 && _initial.validate() == null) {
      final known = _make(_initial.baseUrl);
      try {
        final status = await known.status();
        if (!mounted) {
          known.close();
          return;
        }
        _replace(known);
        setState(() {
          _status = status;
          _stage = 2;
        });
        await known.openSetupNetwork();
        await _scanInternal();
        return;
      } catch (_) {
        if (identical(_client, known)) rethrow;
        known.close();
      }
    }
    if (mounted) setState(() => _stage = 1);
  });
  Future<void> _connectSetup() => _run(() async {
    await _bind();
    final client = _make(setupBoardUrl);
    try {
      final status = await client.status();
      if (!mounted) {
        client.close();
        return;
      }
      _replace(client);
      setState(() {
        _status = status;
        _stage = 2;
      });
      await _scanInternal();
    } catch (_) {
      if (!identical(client, _client)) client.close();
      rethrow;
    }
  });
  Future<void> _scanInternal() async {
    final client = _client!;
    var status = await client.startScan();
    final deadline = DateTime.now().add(const Duration(seconds: 20));
    while (mounted &&
        status.scanState == 'scanning' &&
        DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 650));
      if (!mounted) return;
      status = await client.status();
    }
    if (!mounted) return;
    setState(() {
      _status = status;
      if (_selected.isEmpty &&
          status.networks.any((n) => n.ssid == status.savedSsid)) {
        _selected = status.savedSsid;
      }
      _reuse = status.credentialsSaved && _selected == status.savedSsid;
    });
    if (status.scanState != 'ready') {
      throw StateError('บอร์ดค้นหา Wi-Fi ยังไม่สำเร็จ กดค้นหาอีกครั้งได้');
    }
  }

  Future<BoardWifiStatus> _readStatus() async {
    try {
      return await _client!.status();
    } catch (_) {
      if (_client!.config.baseUrl == setupBoardUrl) rethrow;
      final fallback = _make(setupBoardUrl);
      try {
        final status = await fallback.status();
        _replace(fallback);
        return status;
      } catch (_) {
        fallback.close();
        rethrow;
      }
    }
  }

  Future<void> _watchJob() async {
    final deadline = DateTime.now().add(const Duration(seconds: 70));
    while (mounted && DateTime.now().isBefore(deadline)) {
      BoardWifiStatus? status;
      try {
        status = await _readStatus();
      } catch (_) {
        /* Radio channel/IP may change during association. */
      }
      if (!mounted) return;
      if (status != null) {
        _status = status;
        if (status.requestId == _requestId && status.phase == 'failed') {
          setState(() => _stage = 2);
          throw StateError(
            status.error.isEmpty
                ? 'เชื่อม Wi-Fi ไม่สำเร็จ ตรวจรหัสแล้วลองใหม่'
                : status.error,
          );
        }
        if (status.requestId == _requestId &&
            status.phase == 'connected' &&
            status.connected &&
            status.ssid == _target) {
          setState(() {
            _lanIp = status!.ip;
            _stage = 4;
          });
          return;
        }
      }
      await Future<void>.delayed(const Duration(milliseconds: 1200));
    }
    if (mounted) {
      throw StateError(
        'ยังยืนยันผลไม่ได้ หากบอร์ดเปลี่ยนเครือข่าย ให้เชื่อม Wi-Fi ของบอร์ดอีกครั้ง แล้วกดตรวจผล',
      );
    }
  }

  Future<void> _submit() => _run(() async {
    final ssid = _hidden ? _hiddenName.text : _selected;
    if (ssid.isEmpty) throw StateError('เลือก Wi-Fi บ้านก่อน');
    final open =
        !_hidden &&
        (_status?.networks.any((n) => n.ssid == ssid && n.open) ?? false);
    validateWifiCredentials(
      ssid,
      _password.text,
      reusePassword: _reuse && !_hidden,
      allowOpen: open,
    );
    _target = ssid;
    _requestId = createId();
    setState(() => _stage = 3);
    // A timeout does not prove the board rejected the request. Keep its ID and
    // query its result before allowing another request to replace it.
    try {
      await _client!.submit(
        requestId: _requestId,
        ssid: ssid,
        password: _password.text,
        reusePassword: _reuse && !_hidden,
        allowOpen: open,
      );
    } on BoardWifiRejected {
      if (mounted) setState(() => _stage = 2);
      rethrow;
    } catch (_) {
      // Delivery may have succeeded before the network changed. Query the
      // existing request ID, without submitting a second Wi-Fi change.
    }
    _password.clear();
    if (!mounted) return;
    await _watchJob();
  });
  Future<void> _finish() => _run(() async {
    await _bind();
    final target = _make('https://$_lanIp');
    try {
      final status = await target.status();
      if (!status.connected ||
          status.ssid != _target ||
          status.savedSsid != _target) {
        throw StateError('บอร์ดยังไม่ยืนยัน Wi-Fi บ้านที่เลือก');
      }
    } finally {
      target.close();
    }
    final error = widget.camera
        ? await _app.configureCamera(_config('https://$_lanIp'), _token)
        : await _app.configure(_config('https://$_lanIp'), _token);
    if (error != null) throw StateError(error);
    if (widget.camera) await _app.reconnect();
    await widget.platform.releaseWifi();
    if (!mounted) return;
    setState(() {
      _completed = true;
      _stage = 5;
    });
  });

  String get _deviceName => widget.camera ? 'กล้อง' : 'บอร์ด';
  String get _activity => switch (_stage) {
    0 => 'กำลังตรวจอุปกรณ์ที่บันทึกไว้…',
    1 => 'กำลังตรวจ$_deviceNameและค้นหา Wi-Fi…',
    2 => 'กำลังค้นหา Wi-Fi 2.4 GHz…',
    3 => 'กำลังรอ$_deviceNameเชื่อม Wi-Fi บ้าน…',
    _ => 'กำลังตรวจและบันทึกการเชื่อมต่อ…',
  };

  Widget _button(
    String label,
    VoidCallback? action, {
    IconData icon = Icons.arrow_forward_rounded,
  }) => FilledButton.icon(
    onPressed: action,
    icon: Icon(icon, size: 20),
    label: Text(label, textAlign: TextAlign.center),
  );

  Widget _instruction(String number, String text) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 25,
          height: 25,
          alignment: Alignment.center,
          decoration: const BoxDecoration(
            color: Color(0xFFE7F3F2),
            shape: BoxShape.circle,
          ),
          child: Text(
            number,
            style: const TextStyle(
              color: AquaColors.teal,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(child: Text(text, style: const TextStyle(height: 1.7))),
      ],
    ),
  );

  Widget _pairingField() => TextField(
    key: const ValueKey('wifi-pairing-code'),
    controller: _pairing,
    enabled: !_busy,
    obscureText: true,
    autocorrect: false,
    enableSuggestions: false,
    decoration: InputDecoration(
      labelText: 'รหัสจับคู่$_deviceName',
      helperText: 'จากบัตรประจำเครื่อง · ไม่ใช่รหัส Wi-Fi บ้าน',
      helperMaxLines: 2,
      prefixIcon: const Icon(Icons.key_rounded),
    ),
  );

  List<Widget> _stageContent() {
    switch (_stage) {
      case 0:
        return [
          const Text(
            'เตรียม 3 อย่างนี้ก่อน',
            style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 18),
          _instruction('1', 'จ่ายไฟให้$_deviceName แล้ววางใกล้เราเตอร์'),
          _instruction('2', 'เตรียมชื่อและรหัส Wi-Fi บ้าน 2.4 GHz'),
          _instruction('3', 'เตรียมรหัสจับคู่จากบัตรประจำเครื่อง'),
          if (_savedToken.isNotEmpty) ...[
            const SizedBox(height: 8),
            const ConnectionHint(
              'มีรหัสจับคู่ที่บันทึกไว้แล้ว ไม่ต้องกรอกใหม่',
              icon: Icons.verified_user_outlined,
            ),
            TextButton(
              onPressed: _busy
                  ? null
                  : () => setState(() {
                      _showPairing = !_showPairing;
                      if (!_showPairing) _pairing.clear();
                    }),
              child: Text(
                _showPairing ? 'ใช้รหัสที่บันทึกไว้' : 'ใช้รหัสจับคู่อื่น',
              ),
            ),
          ],
          if (_savedToken.isEmpty || _showPairing) ...[
            const SizedBox(height: 10),
            _pairingField(),
          ],
          const SizedBox(height: 20),
          _button('เริ่มตั้งค่า', _busy || !_loaded ? null : _start),
          const SizedBox(height: 10),
          const Text(
            'ยังไม่มีอุปกรณ์? ย้อนกลับไปเลือก “ดูวิธีเชื่อมต่อ” ได้',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: AquaColors.muted),
          ),
        ];
      case 1:
        return [
          _instruction(
            '1',
            'เปิดตั้งค่า Wi-Fi ของมือถือ แล้วเลือกเครือข่ายด้านล่าง',
          ),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AquaColors.background,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AquaColors.line),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'ชื่อ Wi-Fi ของอุปกรณ์',
                  style: TextStyle(fontSize: 12, color: AquaColors.muted),
                ),
                const SizedBox(height: 6),
                SelectableText(
                  widget.camera ? cameraSetupNetworkName : setupNetworkName,
                  style: const TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.w700,
                    color: AquaColors.blue,
                  ),
                ),
                const Divider(height: 24),
                const Text(
                  'รหัส Wi-Fi ของอุปกรณ์',
                  style: TextStyle(fontSize: 12, color: AquaColors.muted),
                ),
                Row(
                  children: [
                    Expanded(
                      child: SelectableText(
                        _showApPassword
                            ? setupNetworkPassword(_token)
                            : '••••••••••••••••',
                        style: const TextStyle(fontSize: 17),
                      ),
                    ),
                    IconButton(
                      tooltip: _showApPassword
                          ? 'ซ่อนรหัส Wi-Fi บอร์ด'
                          : 'แสดงรหัส Wi-Fi บอร์ด',
                      onPressed: () =>
                          setState(() => _showApPassword = !_showApPassword),
                      icon: Icon(
                        _showApPassword
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                      ),
                    ),
                    IconButton(
                      tooltip: 'คัดลอกรหัส Wi-Fi บอร์ด',
                      onPressed: () async {
                        await Clipboard.setData(
                          ClipboardData(text: setupNetworkPassword(_token)),
                        );
                        if (!mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('คัดลอกรหัส Wi-Fi อุปกรณ์แล้ว'),
                          ),
                        );
                      },
                      icon: const Icon(Icons.copy_rounded),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          const ConnectionHint(
            'ถ้ามือถือแจ้ง “ไม่มีอินเทอร์เน็ต” ให้เชื่อมต่อเครือข่ายนี้ต่อ เพื่อส่ง Wi-Fi บ้านให้อุปกรณ์',
          ),
          const SizedBox(height: 16),
          _button(
            'เปิดหน้าตั้งค่า Wi-Fi',
            _busy ? null : _openSettings,
            icon: Icons.open_in_new_rounded,
          ),
          const SizedBox(height: 18),
          _instruction('2', 'เชื่อมแล้ว กลับมาแอปและกดตรวจ$_deviceName'),
          OutlinedButton.icon(
            onPressed: _busy ? null : _connectSetup,
            icon: const Icon(Icons.search_rounded),
            label: Text(
              'เชื่อม Wi-Fi $_deviceNameแล้ว ตรวจ$_deviceName',
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 12),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: const Text(
              'ไม่พบชื่อ Wi-Fi อุปกรณ์?',
              style: TextStyle(fontSize: 13),
            ),
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(
                  'ตรวจไฟเลี้ยงและวางใกล้มือถือ หากยังไม่พบ ให้ปิดแล้วเปิดไฟเลี้ยง$_deviceName รอสักครู่แล้วค้นหาใหม่',
                  style: const TextStyle(fontSize: 13, height: 1.7),
                ),
              ),
            ],
          ),
        ];
      case 2:
        return [
          const Text(
            'ให้อุปกรณ์ใช้ Wi-Fi บ้านเดียวกับมือถือ',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          const Text(
            'รายการนี้ค้นหาจากบอร์ด จึงแสดงเครือข่ายที่อุปกรณ์ใช้งานได้',
            style: TextStyle(fontSize: 13, color: AquaColors.muted),
          ),
          const SizedBox(height: 18),
          if (!_hidden)
            DropdownButtonFormField<String>(
              key: ValueKey(
                'networks:${_status?.networks.map((n) => n.ssid).join('|')}:$_selected',
              ),
              initialValue:
                  _status?.networks.any((n) => n.ssid == _selected) == true
                  ? _selected
                  : null,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Wi-Fi บ้าน',
                prefixIcon: Icon(Icons.wifi_rounded),
              ),
              items: [
                for (final n in _status?.networks ?? <BoardNetwork>[])
                  DropdownMenuItem(
                    value: n.ssid,
                    child: Text(n.ssid, overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: _busy
                  ? null
                  : (value) => setState(() {
                      _selected = value ?? '';
                      _reuse =
                          _status!.credentialsSaved &&
                          value == _status!.savedSsid;
                      _password.clear();
                    }),
            ),
          if (!_hidden && !_busy && _status?.networks.isEmpty == true) ...[
            const SizedBox(height: 12),
            const ConnectionHint(
              'ยังไม่พบเครือข่าย ลองค้นหาใหม่ หรือกรอกชื่อ Wi-Fi ด้านล่าง',
            ),
          ],
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _busy ? null : () => _run(_scanInternal),
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('ค้นหา Wi-Fi อีกครั้ง'),
            ),
          ),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text(
              'กรอกชื่อ Wi-Fi เอง / เครือข่ายซ่อน',
              style: TextStyle(fontSize: 13),
            ),
            value: _hidden,
            onChanged: _busy
                ? null
                : (value) => setState(() {
                    _hidden = value ?? false;
                    _reuse = false;
                  }),
          ),
          if (_hidden) ...[
            TextField(
              controller: _hiddenName,
              enabled: !_busy,
              autocorrect: false,
              decoration: const InputDecoration(
                labelText: 'ชื่อ Wi-Fi ที่ซ่อนอยู่',
              ),
            ),
            const SizedBox(height: 12),
          ],
          if (!_hidden &&
              _status?.credentialsSaved == true &&
              _selected == _status?.savedSsid)
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text(
                'ใช้รหัส Wi-Fi เดิมที่บอร์ดบันทึกไว้',
                style: TextStyle(fontSize: 13),
              ),
              value: _reuse,
              onChanged: _busy
                  ? null
                  : (value) => setState(() => _reuse = value ?? false),
            ),
          if (!_reuse)
            TextField(
              controller: _password,
              enabled: !_busy,
              obscureText: !_showPassword,
              autocorrect: false,
              enableSuggestions: false,
              decoration: InputDecoration(
                labelText: 'รหัส Wi-Fi บ้าน',
                helperText: 'เครือข่ายเปิดไม่ใช้รหัส ให้เว้นว่าง',
                helperMaxLines: 2,
                suffixIcon: IconButton(
                  tooltip: _showPassword
                      ? 'ซ่อนรหัส Wi-Fi บ้าน'
                      : 'แสดงรหัส Wi-Fi บ้าน',
                  onPressed: () =>
                      setState(() => _showPassword = !_showPassword),
                  icon: Icon(
                    _showPassword
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                  ),
                ),
              ),
            ),
          const SizedBox(height: 18),
          _button(
            'ส่ง Wi-Fi ให้$_deviceName',
            _busy ? null : _submit,
            icon: Icons.wifi_rounded,
          ),
        ];
      case 3:
        return [
          Text(
            'กำลังให้$_deviceNameเชื่อมกับ $_target',
            style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 16),
          const ConnectionHint(
            'ระหว่างเปลี่ยนเครือข่าย สัญญาณอาจหลุดชั่วคราว รอประมาณครึ่งนาที แอปกำลังตรวจผลจากอุปกรณ์',
          ),
          const SizedBox(height: 12),
          if (!_busy) ...[
            const ConnectionHint(
              'ถ้าหลุดจาก Wi-Fi อุปกรณ์ ให้เชื่อมกลับแล้วกดตรวจผล โดยไม่ต้องส่งรหัสซ้ำ',
            ),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: _openSettings,
              child: const Text('เปิดหน้าตั้งค่า Wi-Fi'),
            ),
            const SizedBox(height: 10),
            _button('ตรวจผลการเชื่อมต่อ', () => _run(_watchJob)),
          ],
        ];
      case 4:
        return [
          ConnectionHint(
            '$_deviceNameเชื่อมกับ $_target แล้ว',
            icon: Icons.wifi_rounded,
          ),
          const SizedBox(height: 20),
          _instruction('1', 'กลับไปเชื่อม Wi-Fi $_target บนมือถือ'),
          OutlinedButton.icon(
            onPressed: _busy ? null : _openSettings,
            icon: const Icon(Icons.wifi_rounded),
            label: const Text('กลับไปเชื่อม Wi-Fi บ้าน'),
          ),
          const SizedBox(height: 18),
          _instruction('2', 'กลับมาแอปเพื่อตรวจการเชื่อมต่อและบันทึกอุปกรณ์'),
          _button(
            'ยืนยันและเข้าใช้งาน',
            _busy ? null : _finish,
            icon: Icons.verified_user_outlined,
          ),
          const SizedBox(height: 12),
          const Text(
            'ยังไม่เสร็จจนกว่ามือถือจะติดต่ออุปกรณ์ได้ใน Wi-Fi บ้าน',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: AquaColors.muted),
          ),
        ];
      default:
        return [
          Text(
            widget.camera
                ? 'เพิ่มกล้องเรียบร้อยแล้ว'
                : 'เพิ่มบอร์ดหลักเรียบร้อยแล้ว',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 14),
          Text(
            widget.camera
                ? 'ไปที่ “นับลูกปลา” เพื่อถ่ายภาพจากกล้องได้เลย'
                : 'ดูค่าเซนเซอร์ได้ที่ “ภาพรวม”\nหากมีกล้อง ให้กลับไปเลือก “เพิ่มกล้อง”',
            textAlign: TextAlign.center,
            style: const TextStyle(height: 1.8),
          ),
          const SizedBox(height: 18),
          ConnectionHint(
            'Wi-Fi: $_target\nที่อยู่: $_lanIp',
            icon: Icons.link_rounded,
          ),
          const SizedBox(height: 20),
          _button(
            'เสร็จสิ้น',
            _busy ? null : () => Navigator.of(context).pop(true),
            icon: Icons.check_rounded,
          ),
        ];
    }
  }

  @override
  Widget build(BuildContext context) {
    final step = _stage.clamp(0, 3);
    final titles = [
      'เตรียมอุปกรณ์',
      'เชื่อม Wi-Fi ของ$_deviceName',
      'เลือก Wi-Fi บ้าน',
      'กำลังเชื่อม Wi-Fi',
      'กลับสู่ Wi-Fi บ้าน',
      'เชื่อมต่อสำเร็จ',
    ];
    const descriptions = [
      'ตั้งค่าจากมือถือได้เลย แอปจะพาไปทีละขั้น',
      'เชื่อมกับอุปกรณ์ชั่วคราว เพื่อส่งข้อมูล Wi-Fi บ้าน',
      'เลือกเครือข่าย 2.4 GHz ที่ต้องการให้อุปกรณ์ใช้งาน',
      'กำลังตรวจสถานะจริงจากอุปกรณ์ กรุณาเปิดหน้านี้ไว้',
      'ขั้นสุดท้าย ให้มือถือกับอุปกรณ์อยู่ในเครือข่ายเดียวกัน',
      'ตรวจการเชื่อมต่อและบันทึกอุปกรณ์แล้ว',
    ];
    return PopScope(
      canPop: !_busy,
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.camera ? 'เชื่อมต่อกล้อง' : 'เชื่อมต่อบอร์ดหลัก'),
          automaticallyImplyLeading: !_busy,
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            controller: _scroll,
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 600),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ConnectionJourneyHeader(
                      step: step,
                      title: titles[_stage],
                      subtitle: descriptions[_stage],
                      device: widget.camera
                          ? 'ESP32-CAM · กล้อง'
                          : 'ESP32-S3 · บอร์ดหลัก',
                      busy: _busy,
                      complete: _completed,
                      icon: widget.camera
                          ? Icons.photo_camera_outlined
                          : Icons.router_rounded,
                    ),
                    const SizedBox(height: 24),
                    if (_busy) ...[
                      Semantics(
                        liveRegion: true,
                        child: ConnectionHint(
                          _activity,
                          icon: Icons.sync_rounded,
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                    if (_error != null) ...[
                      Semantics(
                        liveRegion: true,
                        child: ConnectionHint(_error!, error: true),
                      ),
                      const SizedBox(height: 16),
                    ],
                    AnimatedSwitcher(
                      duration: MediaQuery.disableAnimationsOf(context)
                          ? Duration.zero
                          : const Duration(milliseconds: 320),
                      switchInCurve: Curves.easeOutCubic,
                      transitionBuilder: (child, animation) => FadeTransition(
                        opacity: animation,
                        child: SlideTransition(
                          position: Tween<Offset>(
                            begin: const Offset(0, .035),
                            end: Offset.zero,
                          ).animate(animation),
                          child: child,
                        ),
                      ),
                      // Outgoing inputs must not keep semantics or accept taps.
                      layoutBuilder: (current, previous) =>
                          current ?? const SizedBox.shrink(),
                      child: Card(
                        key: ValueKey(_stage),
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: _stageContent(),
                          ),
                        ),
                      ),
                    ),
                    if ((_stage == 1 || _stage == 2) && !_busy)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: TextButton.icon(
                          onPressed: () => setState(() {
                            _stage--;
                            _error = null;
                          }),
                          icon: const Icon(Icons.arrow_back_rounded, size: 18),
                          label: const Text('ย้อนกลับหนึ่งขั้น'),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
