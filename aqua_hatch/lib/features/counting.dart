import 'package:aqua_hatch/app/icons.dart';
import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:go_router/go_router.dart';
import '../app/theme.dart';
import '../app/brand.dart';
import '../core/controller.dart';
import '../core/fish_head_analyzer.dart';
import '../core/models.dart';
import '../core/ui.dart';
import '../core/motion.dart';
import '../core/camera.dart';
import '../core/usb_preview.dart';

class CountingScreen extends ConsumerStatefulWidget {
  const CountingScreen({super.key});
  @override
  ConsumerState<CountingScreen> createState() => _CountingScreenState();
}

class _CountingScreenState extends ConsumerState<CountingScreen> {
  final _transform = TransformationController();
  DeviceCapture? _usbLastFrame;
  bool _usbLive = true;
  bool _workspace = false;
  bool _erasing = false;
  double _markerRadius = 2;
  Uint8List? _bytes;
  String _filename = 'ยังไม่มีภาพ', _model = '';
  String? _captureId;
  String _captureProgress = '';
  String _captureDetails = '';
  DateTime? _receivedAt;
  int _imageGeneration = 0;
  double _aspect = 1.6;
  bool _sample = false,
      _video = false,
      _busy = false,
      _editing = false,
      _reviewed = false,
      _hasResult = false,
      _saved = false;
  int? _aiCount;
  List<CountPoint> _points = [];
  final _undo = <List<CountPoint>>[];
  @override
  void initState() {
    super.initState();
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) _recover();
  }

  Future<void> _recover() async {
    try {
      final data = await ImagePicker().retrieveLostData();
      if (mounted &&
          !_busy &&
          _imageGeneration == 0 &&
          data.files?.isNotEmpty == true) {
        await _load(data.files!.first, video: data.type == RetrieveType.video);
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  void _reset() {
    _workspace = false;
    _transform.value = Matrix4.identity();
    _points = [];
    _undo.clear();
    _editing = false;
    _erasing = false;
    _reviewed = false;
    _hasResult = false;
    _saved = false;
    _aiCount = null;
    _model = '';
  }

  Future<void> _load(XFile file, {bool video = false}) async {
    final generation = ++_imageGeneration;
    if (await file.length() > 50 * 1024 * 1024) {
      throw StateError('เลือกไฟล์ขนาดไม่เกิน 50 MB');
    }
    final bytes = await file.readAsBytes();
    double aspect = 1.6;
    if (!video) {
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      aspect = frame.image.width / frame.image.height;
      frame.image.dispose();
      codec.dispose();
    }
    if (!mounted || generation != _imageGeneration) return;
    setState(() {
      _captureId = null;
      _receivedAt = null;
      _bytes = bytes;
      _filename = file.name;
      _video = video;
      _sample = false;
      _aspect = aspect;
      _reset();
    });
  }

  Future<void> _capture() async {
    if (_busy) return;
    final usb = ref.read(appControllerProvider).usbCameraEnabled;
    final shownFrame =
        usb &&
            _bytes == null &&
            !_sample &&
            _usbLive &&
            _usbLastFrame != null &&
            DateTime.now().difference(_usbLastFrame!.receivedAt).abs() <
                const Duration(seconds: 3)
        ? _usbLastFrame
        : null;
    final generation = ++_imageGeneration;
    setState(() {
      _usbLive = false;
      _busy = true;
      _sample = false;
      _video = false;
      _bytes = null;
      _captureId = null;
      _receivedAt = null;
      _captureProgress = 'กำลังส่งคำสั่งถึงกล้อง…';
      _captureDetails = '';
      _filename = 'รอภาพจากกล้องในเครื่อง';
      _reset();
    });
    try {
      final image =
          shownFrame ??
          await ref
              .read(appControllerProvider.notifier)
              .captureFromDevice(
                createId(),
                cancelled: () => !mounted || generation != _imageGeneration,
                onProgress: (message) {
                  if (mounted && generation == _imageGeneration) {
                    setState(() => _captureProgress = message);
                  }
                },
              );
      final codec = await ui.instantiateImageCodec(image.bytes);
      final frame = await codec.getNextFrame();
      final aspect = frame.image.width / frame.image.height;
      frame.image.dispose();
      codec.dispose();
      if (!mounted || generation != _imageGeneration) return;
      setState(() {
        _bytes = image.bytes;
        _aspect = aspect;
        _captureId = image.id;
        _receivedAt = image.receivedAt;
        _filename = 'กล้อง ${image.cameraId} / ${image.id}';
        _captureProgress = 'ได้รับภาพใหม่จากกล้องแล้ว';
        _captureDetails = [
          if (image.sensor?.isNotEmpty == true) image.sensor!,
          if (image.width != null && image.height != null)
            '${image.width} × ${image.height} พิกเซล',
          if (image.flashUsed == true) 'เปิดแฟลชตอนถ่ายแล้ว',
        ].join(' · ');
      });
    } catch (e) {
      if (mounted && generation == _imageGeneration) {
        setState(
          () => _captureProgress = e.toString().replaceFirst('Bad state: ', ''),
        );
      }
    } finally {
      if (mounted && generation == _imageGeneration) {
        setState(() => _busy = false);
        ref.invalidate(cameraStatusProvider);
      }
    }
  }

  Future<void> _pick(ImageSource source, {bool video = false}) async {
    try {
      final picker = ImagePicker();
      final file = video
          ? await picker.pickVideo(
              source: source,
              maxDuration: const Duration(seconds: 60),
            )
          : await picker.pickImage(source: source, imageQuality: 95);
      if (file != null) await _load(file, video: video);
    } catch (e) {
      if (mounted) {
        showFeedback(context, e.toString().replaceFirst('Bad state: ', ''));
      }
    }
  }

  Future<void> _analyze() async {
    if (_busy || (!_sample && _bytes == null)) return;
    final generation = _imageGeneration;
    setState(() => _busy = true);
    try {
      if (_sample) {
        await Future<void>.delayed(const Duration(milliseconds: 700));
        if (!mounted || generation != _imageGeneration) return;
        setState(() {
          _points = List.of(samplePoints);
          _aiCount = _points.length;
          _model = 'sample-demo';
          _hasResult = true;
          _workspace = true;
          _transform.value = Matrix4.identity();
          _reviewed = false;
          _saved = false;
          _undo.clear();
        });
      } else {
        final controller = ref.read(appControllerProvider.notifier);
        final localAnalyzer = ref.read(fishHeadAnalyzerProvider);
        final result = !_video && localAnalyzer != null
            ? await localAnalyzer(_bytes!)
            : _captureId != null
            ? await controller.analyzeDeviceCapture(_captureId!)
            : await controller.analyze(_bytes!, _filename, _video);
        double? aspect;
        if (result.frameBytes != null) {
          final codec = await ui.instantiateImageCodec(result.frameBytes!);
          final frame = await codec.getNextFrame();
          aspect = frame.image.width / frame.image.height;
          frame.image.dispose();
          codec.dispose();
        }
        if (!mounted || generation != _imageGeneration) return;
        setState(() {
          _points = List.of(result.points);
          _aiCount = _points.length;
          _model = result.model;
          _hasResult = true;
          _workspace = true;
          _transform.value = Matrix4.identity();
          _reviewed = false;
          _saved = false;
          _undo.clear();
          if (result.frameBytes != null) {
            _bytes = result.frameBytes;
            _video = false;
            _filename = 'เฟรมจาก $_filename';
            _aspect = aspect!;
          }
        });
      }
    } catch (e) {
      if (mounted && generation == _imageGeneration) {
        showFeedback(
          context,
          e.toString().replaceFirst(RegExp(r'^(Bad state: |Exception: )'), ''),
        );
      }
    } finally {
      if (mounted && generation == _imageGeneration) {
        setState(() => _busy = false);
      }
    }
  }

  void _tap(Offset position, Size size) {
    if (!_editing || _busy || _video) return;
    final point = CountPoint(
      (position.dx / size.width).clamp(0, 1),
      (position.dy / size.height).clamp(0, 1),
    );
    var index = -1;
    if (_erasing) {
      var closest = double.infinity;
      final limit = (_markerRadius + 3) / _transform.value.getMaxScaleOnAxis();
      for (var i = 0; i < _points.length; i++) {
        final dx = (_points[i].x - point.x) * size.width;
        final dy = (_points[i].y - point.y) * size.height;
        final distance = sqrt(dx * dx + dy * dy);
        if (distance <= limit && distance < closest) {
          closest = distance;
          index = i;
        }
      }
      if (index < 0) return;
    }
    setState(() {
      _undo.add(List.of(_points));
      _points = List.of(_points);
      if (_erasing) {
        _points.removeAt(index);
      } else {
        _points.add(point);
      }
      _reviewed = false;
      _saved = false;
      _hasResult = true;
    });
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    final error = await ref
        .read(appControllerProvider.notifier)
        .saveCount(
          count: _points.length,
          source: _filename,
          method: _sample
              ? 'sample-demo'
              : _aiCount == null
              ? 'manual'
              : '$_model + reviewed',
          demo: _sample,
          aiCount: _aiCount,
        );
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (error == null) _saved = true;
    });
    showFeedback(context, error, success: 'บันทึกผลนับเข้ารอบฟักแล้ว');
  }

  Widget _preview({bool interactive = false}) {
    if (!_sample && _bytes == null) {
      return Container(
        key: const ValueKey('camera-empty-preview'),
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
        decoration: BoxDecoration(
          color: AquaColors.deep,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: .06),
                border: Border.all(color: Colors.white.withValues(alpha: .15)),
              ),
              child: _busy
                  ? const AquaLoader(
                      label: 'กำลังรับภาพ',
                      compact: true,
                      color: AquaColors.lime,
                    )
                  : const CatfishMark(size: 70),
            ),
            const SizedBox(height: 16),
            Text(
              _busy ? 'กำลังรับภาพ' : 'พร้อมเก็บภาพลูกปลา',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      );
    }
    if (_video) {
      return Container(
        height: 180,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AquaColors.background,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                PhosphorIconsRegular.fileVideo,
                size: 44,
                color: AquaColors.blue,
              ),
              const SizedBox(height: 8),
              Text(_filename, maxLines: 2, overflow: TextOverflow.ellipsis),
              const Text(
                'วิเคราะห์เพื่อเลือกเฟรมจากคลิป',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }
    final image = ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: AspectRatio(
        aspectRatio: _aspect,
        child: LayoutBuilder(
          builder: (context, c) => Semantics(
            label: 'ภาพถาด มีจุดนับ ${_points.length} จุด',
            child: GestureDetector(
              key: const ValueKey('count-review-image'),
              onTapUp: interactive
                  ? (d) => _tap(d.localPosition, Size(c.maxWidth, c.maxHeight))
                  : null,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (_sample)
                    CustomPaint(painter: _SampleTrayPainter())
                  else if (_bytes != null)
                    Image.memory(_bytes!, fit: BoxFit.fill),
                  AnimatedBuilder(
                    animation: _transform,
                    builder: (_, _) {
                      final zoom = interactive
                          ? _transform.value.getMaxScaleOnAxis()
                          : 1.0;
                      return CustomPaint(
                        painter: _PointsPainter(
                          _points,
                          radius: _markerRadius / zoom,
                          strokeWidth: 0.9 / zoom,
                        ),
                      );
                    },
                  ),
                  if (!interactive)
                    Positioned(
                      left: 10,
                      top: 10,
                      child: Pill(
                        _sample
                            ? 'ภาพตัวอย่างจำลอง'
                            : _captureId != null
                            ? 'ภาพจากกล้องในเครื่อง'
                            : 'ภาพที่เลือก',
                      ),
                    ),
                  if (_busy)
                    Container(
                      color: AquaColors.deep.withValues(alpha: .76),
                      child: const Center(
                        child: AquaLoader(
                          label: 'กำลังประมวลผล',
                          color: AquaColors.lime,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    if (!interactive) return image;
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: InteractiveViewer(
        transformationController: _transform,
        panEnabled: !_editing && !_busy,
        scaleEnabled: !_editing && !_busy,
        minScale: 1,
        maxScale: 12,
        child: image,
      ),
    );
  }

  void _manualCount() => setState(() {
    _workspace = true;
    _editing = true;
    _erasing = false;
    _hasResult = true;
  });

  void _useSample() => setState(() {
    _imageGeneration++;
    _captureId = null;
    _receivedAt = null;
    _captureProgress = '';
    _sample = true;
    _bytes = null;
    _video = false;
    _filename = 'ภาพถาดตัวอย่าง';
    _aspect = 1.6;
    _reset();
  });

  Widget _history(AppState state) => Card(
    child: ExpansionTile(
      shape: const Border(),
      collapsedShape: const Border(),
      title: const Text(
        'ประวัติผลนับ',
        style: TextStyle(fontWeight: FontWeight.w700),
      ),
      subtitle: Text(
        '${state.counts.length} รายการ · เก็บในมือถือ',
        style: Theme.of(context).textTheme.bodySmall,
      ),
      children: [
        if (state.counts.isEmpty)
          const Padding(
            padding: EdgeInsets.all(18),
            child: Text('เมื่อบันทึกผลนับ ประวัติจะปรากฏที่นี่'),
          ),
        ...state.counts
            .take(8)
            .map(
              (record) => ListTile(
                title: Text(record.batchName),
                subtitle: Text(
                  '${fullTime(record.at)} · ${record.demo
                      ? 'ตัวอย่างจำลอง'
                      : record.aiCount == null
                      ? 'นับด้วยมือ'
                      : 'AI + ตรวจแก้'}',
                ),
                trailing: Text(
                  '${record.count} ตัว',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: AquaColors.blue,
                  ),
                ),
                onTap: () => showDialog<void>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('รายละเอียดผลนับ'),
                    content: SingleChildScrollView(
                      child: Text(
                        'รอบ: ${record.batchName}\nไฟล์: ${record.source}\nวิธี: ${record.method}\nผลก่อนแก้: ${record.aiCount?.toString() ?? 'ไม่ได้ใช้ AI'}\nผลที่ยืนยัน: ${record.count} ตัว\nเวลา: ${fullTime(record.at)}',
                      ),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('ปิด'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
      ],
    ),
  );

  Widget _input(AppState state) {
    final cameraAsync = ref.watch(cameraStatusProvider);
    final camera = cameraAsync.asData?.value;
    final usb = state.usbCameraEnabled;
    final demoCamera =
        state.connection.demo && state.cameraConnection == null && !usb;
    final hasImage = _sample || _bytes != null;
    final directCapture = _captureId != null && state.cameraConnection != null;
    final localAI = !_video && ref.watch(fishHeadAnalyzerProvider) != null;
    final canAI =
        _sample ||
        (_bytes != null &&
            (localAI || (!state.connection.demo && !usb && !directCapture)));
    return PageBody(
      children: [
        Row(
          children: [
            const Expanded(child: PageTitle('นับลูกปลา')),
            IconButton(
              tooltip: 'ประวัติผลนับ',
              onPressed: () => showModalBottomSheet<void>(
                context: context,
                showDragHandle: true,
                isScrollControlled: true,
                builder: (context) => SafeArea(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: _history(state),
                  ),
                ),
              ),
              icon: const Icon(PhosphorIconsRegular.clockCounterClockwise),
            ),
          ],
        ),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AquaColors.deep,
            borderRadius: BorderRadius.circular(30),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(
                    PhosphorIconsRegular.camera,
                    size: 18,
                    color: AquaColors.lime,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      usb ? 'กล้อง USB' : 'ESP32-CAM',
                      style: const TextStyle(
                        color: AquaColors.paper,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  Text(
                    demoCamera
                        ? 'ยังไม่เพิ่มกล้อง'
                        : camera?.ready == true
                        ? 'พร้อมถ่าย'
                        : cameraAsync.isLoading
                        ? 'กำลังเชื่อมต่อ'
                        : 'ออฟไลน์',
                    style: const TextStyle(
                      color: AquaColors.lime,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
              if (camera?.description.isNotEmpty == true)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    camera!.description,
                    style: const TextStyle(
                      color: AquaColors.lime,
                      fontSize: 11,
                    ),
                  ),
                ),
              const SizedBox(height: 14),
              if (usb && _usbLive && !hasImage)
                UsbLivePreview(onFrame: (frame) => _usbLastFrame = frame)
              else if (hasImage)
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 390),
                  child: _preview(),
                )
              else
                SizedBox(
                  height: MediaQuery.sizeOf(context).height < 700 ? 235 : 300,
                  child: Center(child: _preview()),
                ),
              if (_receivedAt != null && _captureDetails.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(
                    _captureDetails,
                    key: const ValueKey('camera-photo-details'),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: AquaColors.lime,
                      fontSize: 11,
                    ),
                  ),
                ),
              const SizedBox(height: 18),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _CaptureAction(
                    icon: PhosphorIconsRegular.image,
                    label: 'เลือกภาพ',
                    onTap: _busy ? null : () => _pick(ImageSource.gallery),
                  ),
                  Column(
                    children: [
                      Semantics(
                        label: 'ถ่ายภาพ',
                        button: true,
                        child: SizedBox.square(
                          dimension: 74,
                          child: OutlinedButton(
                            key: const ValueKey('device-capture-button'),
                            onPressed:
                                _busy || demoCamera || camera?.ready != true
                                ? null
                                : _capture,
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.all(5),
                              side: const BorderSide(
                                color: AquaColors.lime,
                                width: 2,
                              ),
                              shape: const CircleBorder(),
                            ),
                            child: Container(
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: camera?.ready == true
                                    ? AquaColors.lime
                                    : AquaColors.lime.withValues(alpha: .22),
                              ),
                              child: Center(
                                child: Icon(
                                  PhosphorIconsRegular.camera,
                                  color: camera?.ready == true
                                      ? AquaColors.deep
                                      : AquaColors.lime,
                                  size: 28,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 7),
                      Text(
                        usb && _usbLive && !hasImage
                            ? 'หยุดภาพ'
                            : _captureId == null
                            ? 'ถ่ายภาพ'
                            : 'ถ่ายใหม่',
                        style: const TextStyle(
                          color: AquaColors.paper,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                  _CaptureAction(
                    icon: PhosphorIconsRegular.scan,
                    label: 'เพิ่มกล้อง',
                    onTap: _busy ? null : () => context.go('/settings'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
        if (!_busy && _captureId == null && _captureProgress.isNotEmpty) ...[
          const SizedBox(height: 12),
          Semantics(
            liveRegion: true,
            child: Notice(_captureProgress, warning: true),
          ),
        ],
        if (hasImage) ...[
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _busy || !canAI ? null : _analyze,
              icon: const Icon(PhosphorIconsRegular.scan),
              label: Text(
                _busy
                    ? 'กำลังประมวลผล…'
                    : _sample
                    ? 'ลองนับภาพตัวอย่าง'
                    : !canAI
                    ? 'AI ยังไม่พร้อมใช้งาน'
                    : 'วิเคราะห์ด้วย AI',
              ),
            ),
          ),
          if (!_video)
            Center(
              child: TextButton.icon(
                onPressed: _busy ? null : _manualCount,
                icon: const Icon(PhosphorIconsRegular.handTap),
                label: const Text('นับด้วยมือ'),
              ),
            ),
        ],
        if (usb && (!_usbLive || hasImage)) ...[
          const SizedBox(height: 12),
          OutlinedButton.icon(
            key: const ValueKey('usb-resume-preview'),
            onPressed: _busy
                ? null
                : () => setState(() {
                    ++_imageGeneration;
                    _bytes = null;
                    _captureId = null;
                    _receivedAt = null;
                    _sample = false;
                    _video = false;
                    _captureProgress = '';
                    _usbLastFrame = null;
                    _reset();
                    _usbLive = true;
                  }),
            icon: const Icon(PhosphorIconsRegular.videoCamera),
            label: const Text('กลับไปดูภาพสด USB'),
          ),
        ],
        const SizedBox(height: 16),
        ExpansionTile(
          key: const PageStorageKey('count-import-options'),
          tilePadding: const EdgeInsets.symmetric(horizontal: 4),
          shape: const Border(),
          collapsedShape: const Border(),
          title: const Text('แหล่งภาพอื่น', style: TextStyle(fontSize: 13)),
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                OutlinedButton.icon(
                  onPressed: _busy ? null : () => _pick(ImageSource.camera),
                  icon: const Icon(PhosphorIconsRegular.camera, size: 18),
                  label: const Text('กล้องมือถือ'),
                ),
                OutlinedButton.icon(
                  onPressed: _busy
                      ? null
                      : () => _pick(ImageSource.gallery, video: true),
                  icon: const Icon(PhosphorIconsRegular.filmStrip, size: 18),
                  label: const Text('เลือกคลิป'),
                ),
              ],
            ),
          ],
        ),
        Center(
          child: TextButton(
            onPressed: _busy ? null : _useSample,
            child: const Text('ใช้ภาพตัวอย่าง'),
          ),
        ),
        if (!demoCamera && camera?.ready != true && !hasImage)
          Center(
            child: TextButton.icon(
              onPressed: cameraAsync.isLoading
                  ? null
                  : () => ref.invalidate(cameraStatusProvider),
              icon: const Icon(PhosphorIconsRegular.arrowClockwise),
              label: const Text('ตรวจสถานะกล้องอีกครั้ง'),
            ),
          ),
        if (_hasResult)
          TextButton(
            onPressed: () => setState(() => _workspace = true),
            child: const Text('กลับไปตรวจผลนับ'),
          ),
      ],
    );
  }

  Widget _review(AppState state) => LayoutBuilder(
    builder: (context, c) => Column(
      key: const ValueKey('count-workspace'),
      children: [
        Expanded(
          child: SingleChildScrollView(
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1000),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(18, 8, 18, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          TextButton.icon(
                            onPressed: _busy
                                ? null
                                : () => setState(() => _workspace = false),
                            icon: const Icon(PhosphorIconsRegular.arrowLeft),
                            label: const Text('เลือกภาพ'),
                          ),
                          Expanded(
                            child: Align(
                              alignment: Alignment.centerRight,
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Semantics(
                                  liveRegion: true,
                                  label: 'จำนวน ${_points.length} ตัวในภาพ',
                                  excludeSemantics: true,
                                  child: Text(
                                    _points.length.toString(),
                                    style: const TextStyle(
                                      fontSize: 32,
                                      fontWeight: FontWeight.w700,
                                      color: AquaColors.deep,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Text('ตัวในภาพ'),
                        ],
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        height: (c.maxHeight * .40).clamp(140.0, 370.0),
                        child: Center(child: _preview(interactive: true)),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 4,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          SegmentedButton<String>(
                            key: const ValueKey('count-tool-selector'),
                            showSelectedIcon: false,
                            style: const ButtonStyle(
                              padding: WidgetStatePropertyAll(
                                EdgeInsets.symmetric(horizontal: 8),
                              ),
                            ),
                            segments: const [
                              ButtonSegment(
                                value: 'move',
                                icon: Icon(
                                  PhosphorIconsRegular.magnifyingGlassPlus,
                                  size: 18,
                                ),
                                label: Text('ซูม'),
                              ),
                              ButtonSegment(
                                value: 'add',
                                icon: Icon(
                                  PhosphorIconsRegular.plusCircle,
                                  size: 18,
                                ),
                                label: Text('เพิ่มจุด'),
                              ),
                              ButtonSegment(
                                value: 'remove',
                                icon: Icon(
                                  PhosphorIconsRegular.minusCircle,
                                  size: 18,
                                ),
                                label: Text('ลบจุด'),
                              ),
                            ],
                            selected: {
                              !_editing
                                  ? 'move'
                                  : _erasing
                                  ? 'remove'
                                  : 'add',
                            },
                            onSelectionChanged: _busy
                                ? null
                                : (s) => setState(() {
                                    _editing = s.first != 'move';
                                    _erasing = s.first == 'remove';
                                  }),
                          ),
                          IconButton(
                            tooltip: 'ย้อนกลับ',
                            onPressed: _undo.isEmpty || _busy
                                ? null
                                : () => setState(() {
                                    _points = _undo.removeLast();
                                    _reviewed = false;
                                    _saved = false;
                                  }),
                            icon: const Icon(
                              PhosphorIconsRegular.arrowCounterClockwise,
                            ),
                          ),
                          PopupMenuButton<String>(
                            tooltip: 'เครื่องมือเพิ่มเติม',
                            enabled: !_busy,
                            icon: const Icon(PhosphorIconsRegular.dotsThree),
                            itemBuilder: (_) => [
                              const PopupMenuItem(
                                value: 'zoom',
                                child: Text('คืนขนาดภาพ'),
                              ),
                              PopupMenuItem(
                                value: 'clear',
                                enabled: _points.isNotEmpty,
                                child: const Text('ล้างจุดทั้งหมด'),
                              ),
                            ],
                            onSelected: (action) {
                              if (action == 'zoom') {
                                _transform.value = Matrix4.identity();
                              } else {
                                setState(() {
                                  _undo.add(List.of(_points));
                                  _points = [];
                                  _reviewed = false;
                                  _saved = false;
                                });
                              }
                            },
                          ),
                        ],
                      ),
                      Row(
                        children: [
                          const Text('ขนาดจุด'),
                          Expanded(
                            child: Slider(
                              key: const ValueKey('count-marker-size'),
                              value: _markerRadius,
                              min: 1,
                              max: 5,
                              divisions: 8,
                              onChanged: _busy
                                  ? null
                                  : (v) => setState(() => _markerRadius = v),
                            ),
                          ),
                        ],
                      ),
                      Text(
                        _editing
                            ? _erasing
                                  ? 'แตะจุดที่ต้องการลบ'
                                  : 'แตะหัวลูกปลาเพื่อเพิ่มจุด'
                            : 'ใช้สองนิ้วซูมภาพ',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading,
                        value: _reviewed,
                        onChanged: _hasResult && !_busy && !_saved
                            ? (v) => setState(() => _reviewed = v ?? false)
                            : null,
                        title: const Text(
                          'ตรวจสอบจำนวนในภาพแล้ว',
                          style: TextStyle(fontSize: 14),
                        ),
                      ),
                      Text(
                        _sample
                            ? 'ผลจากภาพตัวอย่าง'
                            : _aiCount == null
                            ? 'นับด้วยมือ'
                            : 'AI ก่อนแก้ $_aiCount ตัว · ตรวจแก้ได้',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      Text(
                        'รอบ: ${state.batch?.name ?? 'ยังไม่มีรอบฟัก'}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      if (state.batch == null)
                        TextButton(
                          onPressed: state.batchBusy
                              ? null
                              : () => showBatchDialog(
                                  context,
                                  ref.read(appControllerProvider.notifier),
                                ),
                          child: const Text('เริ่มรอบฟัก'),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        Container(
          width: double.infinity,
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(top: BorderSide(color: AquaColors.line)),
          ),
          padding: const EdgeInsets.fromLTRB(18, 10, 18, 12),
          child: SafeArea(
            top: false,
            child: Align(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed:
                        _hasResult &&
                            _reviewed &&
                            !_busy &&
                            !_saved &&
                            state.batch != null
                        ? _save
                        : null,
                    icon: Icon(
                      _saved
                          ? PhosphorIconsRegular.checkCircle
                          : PhosphorIconsRegular.floppyDisk,
                    ),
                    label: Text(
                      _saved
                          ? 'บันทึกแล้ว'
                          : _busy
                          ? 'กำลังบันทึก…'
                          : 'บันทึกผลนับ',
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(appControllerProvider);
    ref.listen<ConnectionConfig>(
      appControllerProvider.select((s) => s.connection),
      (before, after) {
        if (before?.demo == after.demo &&
            before?.baseUrl == after.baseUrl &&
            before?.deviceId == after.deviceId) {
          return;
        }
        setState(() {
          _imageGeneration++;
          _busy = false;
          _bytes = null;
          _sample = false;
          _video = false;
          _captureId = null;
          _receivedAt = null;
          _captureProgress = '';
          _filename = 'ยังไม่มีภาพ';
          _reset();
        });
      },
    );
    ref.listen<ConnectionConfig?>(
      appControllerProvider.select((s) => s.cameraConnection),
      (before, after) {
        if (before?.baseUrl == after?.baseUrl &&
            before?.deviceId == after?.deviceId) {
          return;
        }
        setState(() {
          _imageGeneration++;
          _busy = false;
          _bytes = null;
          _sample = false;
          _captureId = null;
          _receivedAt = null;
          _captureProgress = '';
          _filename = 'ยังไม่มีภาพ';
          _reset();
        });
      },
    );
    return _workspace ? _review(state) : _input(state);
  }
}

class _SampleTrayPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = const LinearGradient(
          colors: [Color(0xFFD7EAF0), Color(0xFFC0DDE5)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ).createShader(Offset.zero & size),
    );
    final tray = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        size.width * .03,
        size.height * .04,
        size.width * .94,
        size.height * .92,
      ),
      const Radius.circular(20),
    );
    canvas.drawRRect(
      tray,
      Paint()
        ..color = const Color(0xFF9BB9C3)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4,
    );
    for (final point in samplePoints) {
      final center = Offset(point.x * size.width, point.y * size.height);
      final angle = Random((point.x * 1000).round()).nextDouble() * pi;
      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.rotate(angle);
      final scale = size.width / 600;
      canvas.scale(scale, scale);
      canvas.drawOval(
        const Rect.fromLTWH(-7, -3, 14, 6),
        Paint()..color = const Color(0xFF304951),
      );
      canvas.drawPath(
        Path()
          ..moveTo(5, 0)
          ..quadraticBezierTo(13, 5, 18, 1),
        Paint()
          ..color = const Color(0xFF304951)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5
          ..strokeCap = StrokeCap.round,
      );
      canvas.drawCircle(
        const Offset(-4, -1),
        .8,
        Paint()..color = Colors.white,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _SampleTrayPainter old) => false;
}

class _PointsPainter extends CustomPainter {
  final List<CountPoint> points;
  final double radius, strokeWidth;
  _PointsPainter(
    this.points, {
    required this.radius,
    required this.strokeWidth,
  });
  @override
  void paint(Canvas canvas, Size size) {
    for (final point in points) {
      final at = Offset(point.x * size.width, point.y * size.height);
      canvas.drawCircle(
        at,
        radius,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth * 2,
      );
      canvas.drawCircle(
        at,
        radius,
        Paint()..color = AquaColors.teal.withValues(alpha: .1),
      );
      canvas.drawCircle(
        at,
        radius,
        Paint()
          ..color = AquaColors.teal
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth,
      );
      canvas.drawCircle(at, radius * .28, Paint()..color = AquaColors.teal);
    }
  }

  @override
  bool shouldRepaint(covariant _PointsPainter old) =>
      old.points != points ||
      old.radius != radius ||
      old.strokeWidth != strokeWidth;
}

class _CaptureAction extends StatelessWidget {
  const _CaptureAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(12),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
      child: Column(
        children: [
          Icon(
            icon,
            color: onTap == null ? AquaColors.muted : AquaColors.lime,
            size: 24,
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: const TextStyle(color: AquaColors.paper, fontSize: 12),
          ),
        ],
      ),
    ),
  );
}
