import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../app/theme.dart';
import '../core/board_wifi.dart';
import '../core/controller.dart';
import '../core/models.dart';
import '../core/wifi_platform.dart';

class WifiSetupScreen extends ConsumerStatefulWidget {
  final WifiPlatform platform;
  final BoardWifiClient Function(ConnectionConfig, String)? clientFactory;
  const WifiSetupScreen({
    super.key,
    this.platform = const WifiPlatform(),
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

  @override
  void initState() {
    super.initState();
    _app = ref.read(appControllerProvider.notifier);
    _initial = ref.read(appControllerProvider).connection;
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
      BoardWifiClient(_config(url), _token);
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
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (error) {
      if (mounted) setState(() => _error = _friendly(error));
    } finally {
      if (mounted) setState(() => _busy = false);
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
        _status = status;
        _stage = 2;
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
      _status = status;
      _stage = 2;
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
    final error = await _app.configure(_config('https://$_lanIp'), _token);
    if (error != null) throw StateError(error);
    await widget.platform.releaseWifi();
    if (!mounted) return;
    _completed = true;
    Navigator.of(context).pop(true);
  });

  Widget _button(
    String label,
    VoidCallback? action, {
    IconData icon = Icons.arrow_forward_rounded,
  }) => SizedBox(
    width: double.infinity,
    child: FilledButton.icon(
      onPressed: action,
      icon: Icon(icon, size: 20),
      label: Text(label),
    ),
  );
  Widget _notice(String message) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: AquaColors.teal.withValues(alpha: .07),
      borderRadius: BorderRadius.circular(16),
    ),
    child: Text(
      message,
      style: const TextStyle(color: AquaColors.teal, height: 1.6),
    ),
  );
  @override
  Widget build(BuildContext context) {
    final titles = [
      'เริ่มตั้งค่าเครื่อง',
      'เชื่อม Wi-Fi ของบอร์ด',
      'เลือก Wi-Fi บ้าน',
      'กำลังเชื่อม Wi-Fi',
      'พร้อมเข้าใช้งาน',
    ];
    return PopScope(
      canPop: !_busy,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('ตั้ง Wi-Fi ให้บอร์ด'),
          automaticallyImplyLeading: !_busy,
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 580),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(22),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [AquaColors.deep, AquaColors.navy],
                        ),
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            Icons.wifi_rounded,
                            color: Colors.white,
                            size: 36,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            titles[_stage],
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 25,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'ตั้งค่าจากมือถือ แล้วใช้งานกับบอร์ดได้โดยไม่เปิดคอม',
                            style: TextStyle(
                              color: Colors.white70,
                              height: 1.6,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    if (_busy) ...[
                      const LinearProgressIndicator(),
                      const SizedBox(height: 16),
                    ],
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (_stage == 0) ...[
                              const Text(
                                'สิ่งที่ต้องเตรียม',
                                style: TextStyle(
                                  fontSize: 19,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 12),
                              const Text(
                                '1. จ่ายไฟให้บอร์ด\n2. ชื่อและรหัส Wi-Fi บ้านย่าน 2.4 GHz\n3. รหัสจับคู่จากบัตรประจำเครื่อง',
                                style: TextStyle(height: 1.9),
                              ),
                              const SizedBox(height: 18),
                              if (_savedToken.isNotEmpty)
                                _notice(
                                  'ใช้รหัสบอร์ดที่บันทึกไว้แล้ว เว้นช่องด้านล่างว่างได้',
                                ),
                              const SizedBox(height: 12),
                              TextField(
                                controller: _pairing,
                                obscureText: true,
                                autocorrect: false,
                                enableSuggestions: false,
                                decoration: const InputDecoration(
                                  labelText: 'รหัสจับคู่บอร์ด',
                                  helperText: 'เป็นคนละรหัสกับ Wi-Fi บ้าน',
                                ),
                              ),
                              const SizedBox(height: 20),
                              _button(
                                'เริ่มตั้งค่า',
                                _busy || !_loaded ? null : _start,
                              ),
                            ],
                            if (_stage == 1) ...[
                              const Text(
                                'เปิด Wi-Fi ในมือถือ แล้วเลือกเครือข่ายนี้',
                                style: TextStyle(height: 1.7),
                              ),
                              const SizedBox(height: 16),
                              const SelectableText(
                                setupNetworkName,
                                style: TextStyle(
                                  fontSize: 23,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  Expanded(
                                    child: SelectableText(
                                      _showApPassword
                                          ? setupNetworkPassword(_token)
                                          : '••••••••••••••••',
                                      style: const TextStyle(fontSize: 19),
                                    ),
                                  ),
                                  IconButton(
                                    tooltip: _showApPassword
                                        ? 'ซ่อนรหัส Wi-Fi บอร์ด'
                                        : 'แสดงรหัส Wi-Fi บอร์ด',
                                    onPressed: () => setState(
                                      () => _showApPassword = !_showApPassword,
                                    ),
                                    icon: Icon(
                                      _showApPassword
                                          ? Icons.visibility_off
                                          : Icons.visibility,
                                    ),
                                  ),
                                  IconButton(
                                    tooltip: 'คัดลอกรหัส Wi-Fi บอร์ด',
                                    onPressed: () => Clipboard.setData(
                                      ClipboardData(
                                        text: setupNetworkPassword(_token),
                                      ),
                                    ),
                                    icon: const Icon(Icons.copy_rounded),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 14),
                              _notice(
                                'ถ้ามือถือแจ้งว่าไม่มีอินเทอร์เน็ต ให้เลือกเชื่อมต่อเครือข่ายนี้ต่อ แล้วกลับมาแอป\nหากไม่พบชื่อ ให้ปิดแล้วเปิดไฟเลี้ยงบอร์ดใหม่',
                              ),
                              const SizedBox(height: 18),
                              OutlinedButton.icon(
                                onPressed: _openSettings,
                                icon: const Icon(Icons.settings_rounded),
                                label: const Text('เปิดหน้าตั้งค่า Wi-Fi'),
                              ),
                              const SizedBox(height: 12),
                              _button(
                                'เชื่อม Wi-Fi บอร์ดแล้ว ตรวจบอร์ด',
                                _busy ? null : _connectSetup,
                              ),
                            ],
                            if (_stage == 2) ...[
                              if (_status?.savedSsid.isNotEmpty == true) ...[
                                _notice(
                                  'Wi-Fi ที่บอร์ดบันทึกไว้: ${_status!.savedSsid}',
                                ),
                                const SizedBox(height: 16),
                              ],
                              const Text(
                                'เครือข่าย 2.4 GHz ที่บอร์ดค้นพบ',
                                style: TextStyle(fontWeight: FontWeight.w700),
                              ),
                              const SizedBox(height: 12),
                              if (!_hidden)
                                DropdownButtonFormField<String>(
                                  key: ValueKey(
                                    'networks:${_status?.networks.map((n) => n.ssid).join('|')}:$_selected',
                                  ),
                                  initialValue:
                                      _status?.networks.any(
                                            (n) => n.ssid == _selected,
                                          ) ==
                                          true
                                      ? _selected
                                      : null,
                                  isExpanded: true,
                                  decoration: const InputDecoration(
                                    labelText: 'Wi-Fi บ้าน',
                                  ),
                                  items: [
                                    for (final n
                                        in _status?.networks ??
                                            <BoardNetwork>[])
                                      DropdownMenuItem(
                                        value: n.ssid,
                                        child: Text(
                                          n.ssid,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                  ],
                                  onChanged: _busy
                                      ? null
                                      : (value) => setState(() {
                                          _selected = value ?? '';
                                          _reuse =
                                              _status!.credentialsSaved &&
                                              value == _status!.savedSsid;
                                        }),
                                ),
                              TextButton.icon(
                                onPressed: _busy
                                    ? null
                                    : () => _run(_scanInternal),
                                icon: const Icon(Icons.refresh_rounded),
                                label: const Text('ค้นหา Wi-Fi อีกครั้ง'),
                              ),
                              CheckboxListTile(
                                contentPadding: EdgeInsets.zero,
                                title: const Text(
                                  'กรอกชื่อเครือข่ายที่ซ่อนอยู่',
                                ),
                                value: _hidden,
                                onChanged: _busy
                                    ? null
                                    : (value) => setState(() {
                                        _hidden = value ?? false;
                                        _reuse = false;
                                      }),
                              ),
                              if (_hidden)
                                TextField(
                                  controller: _hiddenName,
                                  decoration: const InputDecoration(
                                    labelText: 'ชื่อ Wi-Fi ที่ซ่อนอยู่',
                                  ),
                                ),
                              if (!_hidden &&
                                  _status?.credentialsSaved == true &&
                                  _selected == _status?.savedSsid)
                                CheckboxListTile(
                                  contentPadding: EdgeInsets.zero,
                                  title: const Text(
                                    'ใช้รหัส Wi-Fi เดิมที่บอร์ดบันทึกไว้',
                                  ),
                                  value: _reuse,
                                  onChanged: _busy
                                      ? null
                                      : (value) => setState(
                                          () => _reuse = value ?? false,
                                        ),
                                ),
                              if (!_reuse)
                                TextField(
                                  controller: _password,
                                  obscureText: true,
                                  autocorrect: false,
                                  enableSuggestions: false,
                                  decoration: const InputDecoration(
                                    labelText: 'รหัส Wi-Fi บ้าน',
                                    helperText:
                                        'เว้นว่างได้เมื่อเครือข่ายเปิดไม่ใช้รหัส',
                                  ),
                                ),
                              const SizedBox(height: 18),
                              _button(
                                'ส่ง Wi-Fi ให้บอร์ด',
                                _busy ? null : _submit,
                                icon: Icons.wifi_rounded,
                              ),
                            ],
                            if (_stage == 3) ...[
                              Text(
                                'กำลังให้บอร์ดเชื่อมกับ $_target',
                                style: const TextStyle(
                                  fontSize: 19,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 14),
                              _notice(
                                'บอร์ดอาจเปลี่ยนช่องสัญญาณระหว่างเชื่อมต่อ ใช้เวลาประมาณครึ่งนาที\nถ้าหลุดจาก Wi-Fi บอร์ด ให้เชื่อมกลับแล้วกดตรวจผล',
                              ),
                              const SizedBox(height: 16),
                              OutlinedButton(
                                onPressed: _openSettings,
                                child: const Text('เปิดหน้าตั้งค่า Wi-Fi'),
                              ),
                              _button(
                                'ตรวจผลการเชื่อมต่อ',
                                _busy ? null : () => _run(_watchJob),
                              ),
                            ],
                            if (_stage == 4) ...[
                              const Icon(
                                Icons.check_circle_rounded,
                                color: AquaColors.teal,
                                size: 56,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'บอร์ดเชื่อมกับ $_target แล้ว',
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 16),
                              _notice(
                                'กลับไปเชื่อม Wi-Fi บ้านบนมือถือ แล้วกดปุ่มด้านล่าง แอปจะบันทึกเครื่องและเชื่อมต่อให้',
                              ),
                              const SizedBox(height: 16),
                              OutlinedButton.icon(
                                onPressed: _openSettings,
                                icon: const Icon(Icons.wifi_rounded),
                                label: const Text('กลับไปเชื่อม Wi-Fi บ้าน'),
                              ),
                              const SizedBox(height: 12),
                              _button(
                                'ยืนยันและเข้าใช้งาน',
                                _busy ? null : _finish,
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 16),
                      Semantics(
                        liveRegion: true,
                        child: Text(
                          _error!,
                          style: const TextStyle(
                            color: AquaColors.red,
                            height: 1.7,
                          ),
                        ),
                      ),
                    ],
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
