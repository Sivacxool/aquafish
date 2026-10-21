import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:go_router/go_router.dart';
import '../app/theme.dart';
import '../core/controller.dart';
import '../core/models.dart';
import '../core/ui.dart';

class CountingScreen extends ConsumerStatefulWidget {
  const CountingScreen({super.key});
  @override
  ConsumerState<CountingScreen> createState() => _CountingScreenState();
}

class _CountingScreenState extends ConsumerState<CountingScreen> {
  final _transform = TransformationController();
  bool _workspace = false;
  Uint8List? _bytes;
  String _filename = 'ยังไม่มีภาพ', _model = '';
  String? _captureId;
  String _captureProgress = '';
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
      if (data.files?.isNotEmpty == true) {
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
    final generation = ++_imageGeneration;
    setState(() {
      _busy = true;
      _sample = false;
      _video = false;
      _bytes = null;
      _captureId = null;
      _receivedAt = null;
      _captureProgress = 'กำลังส่งคำสั่งถึงกล้อง…';
      _filename = 'รอภาพจากกล้องในเครื่อง';
      _reset();
    });
    try {
      final image = await ref
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
        _captureProgress =
            'ได้รับภาพใหม่จากกล้องแล้ว พร้อมวิเคราะห์หรือนับด้วยมือ';
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
        final result = _captureId != null
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
    final index = _points.indexWhere(
      (p) => sqrt(pow(p.x - point.x, 2) + pow(p.y - point.y, 2)) < .03,
    );
    setState(() {
      _undo.add(List.of(_points));
      _points = List.of(_points);
      if (index >= 0) {
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
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF123F50), Color(0xFF082A3B)],
          ),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: .06),
                border: Border.all(color: Colors.white.withValues(alpha: .15)),
              ),
              child: _busy
                  ? const SizedBox(
                      width: 32,
                      height: 32,
                      child: CircularProgressIndicator(
                        color: Color(0xFF79E0D0),
                        strokeWidth: 2,
                      ),
                    )
                  : const Icon(
                      Icons.linked_camera_outlined,
                      size: 32,
                      color: Color(0xFF79E0D0),
                    ),
            ),
            const SizedBox(height: 16),
            Text(
              _busy ? 'กำลังรอภาพจากกล้อง' : 'มองเห็นถาดฟักจากที่นี่',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'กดถ่ายเพื่อรับภาพใหม่จากกล้องในเครื่อง',
              textAlign: TextAlign.center,
              style: TextStyle(color: Color(0xFFBED4DF), fontSize: 12),
            ),
            const SizedBox(height: 16),
            const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.crop_free_rounded,
                  size: 15,
                  color: Color(0xFF8EB2C3),
                ),
                SizedBox(width: 6),
                Flexible(
                  child: Text(
                    'ภาพนิ่งตามคำสั่ง · ไม่ใช่ภาพสด',
                    style: TextStyle(color: Color(0xFF8EB2C3), fontSize: 11),
                  ),
                ),
              ],
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
                Icons.video_file_outlined,
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
                  CustomPaint(painter: _PointsPainter(_points)),
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
                      color: Colors.white.withValues(alpha: .6),
                      child: const Center(child: CircularProgressIndicator()),
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
        maxScale: 5,
        child: image,
      ),
    );
  }

  Widget _steps() => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Row(
      children: ['1  รับภาพ', '2  ตรวจนับ', '3  บันทึก'].asMap().entries.map((
        entry,
      ) {
        final active =
            entry.key ==
            (_saved
                ? 2
                : _workspace
                ? 1
                : 0);
        return Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
            decoration: BoxDecoration(
              color: active ? const Color(0xFFE0F1F1) : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              entry.value,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: active ? AquaColors.deep : AquaColors.muted,
                fontWeight: active ? FontWeight.w700 : FontWeight.w400,
              ),
            ),
          ),
        );
      }).toList(),
    ),
  );

  void _manualCount() => setState(() {
    _workspace = true;
    _editing = true;
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
    final hasImage = _sample || _bytes != null;
    final canAI = _sample || (_bytes != null && !state.connection.demo);
    return PageBody(
      children: [
        const PageTitle(
          'กล้องและนับลูกปลา',
          'รับภาพจากเครื่องฟัก แล้วตรวจนับในภาพเดียวกัน',
        ),
        _steps(),
        Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: Surface(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'กล้องในเครื่อง',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      Pill(
                        state.connection.demo
                            ? 'โหมดทดลอง'
                            : camera?.ready == true
                            ? 'พร้อมถ่าย'
                            : 'ยังไม่เชื่อมต่อ',
                        color: camera?.ready == true
                            ? AquaColors.teal
                            : AquaColors.muted,
                        icon: camera?.ready == true
                            ? Icons.check_circle_outline_rounded
                            : Icons.wifi_off_rounded,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (hasImage)
                    Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 300),
                        child: _preview(),
                      ),
                    )
                  else
                    _preview(),
                  const SizedBox(height: 14),
                  FilledButton.icon(
                    key: const ValueKey('device-capture-button'),
                    onPressed:
                        _busy || state.connection.demo || camera?.ready != true
                        ? null
                        : _capture,
                    icon: const Icon(Icons.camera_alt_rounded),
                    label: Text(
                      _captureId == null
                          ? 'ถ่ายภาพจากกล้องในเครื่อง'
                          : 'ถ่ายภาพใหม่จากกล้องในเครื่อง',
                    ),
                  ),
                  if (_captureProgress.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Semantics(
                      liveRegion: true,
                      child: Notice(
                        _captureProgress,
                        warning: !_busy && _captureId == null,
                      ),
                    ),
                  ],
                  if (_receivedAt != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      'รับภาพเมื่อ ${fullTime(_receivedAt!)}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                  if (!hasImage && !_busy) ...[
                    const SizedBox(height: 12),
                    Text(
                      state.connection.demo
                          ? 'เชื่อมต่อเครื่องจริงในตั้งค่าเพื่อใช้กล้อง หรือทดลองขั้นตอนนับด้านล่าง'
                          : camera?.message ?? 'กำลังตรวจสถานะกล้อง…',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    Row(
                      children: [
                        TextButton.icon(
                          onPressed: () => context.go('/settings'),
                          icon: const Icon(Icons.tune_rounded, size: 17),
                          label: const Text('ตั้งค่าการเชื่อมต่อ'),
                        ),
                        const Spacer(),
                        IconButton(
                          tooltip: 'ตรวจสถานะกล้องอีกครั้ง',
                          onPressed: cameraAsync.isLoading
                              ? null
                              : () => ref.invalidate(cameraStatusProvider),
                          icon: const Icon(Icons.refresh_rounded),
                        ),
                      ],
                    ),
                  ],
                  if (hasImage) ...[
                    const SizedBox(height: 14),
                    FilledButton.tonalIcon(
                      onPressed: _busy || !canAI ? null : _analyze,
                      icon: Icon(
                        _busy
                            ? Icons.hourglass_top_rounded
                            : Icons.auto_awesome_rounded,
                      ),
                      label: Text(
                        _busy
                            ? 'กำลังประมวลผล…'
                            : _sample
                            ? 'ลองนับภาพตัวอย่าง'
                            : 'วิเคราะห์ด้วย AI',
                      ),
                    ),
                    if (!_video)
                      TextButton.icon(
                        onPressed: _busy ? null : _manualCount,
                        icon: const Icon(Icons.touch_app_outlined),
                        label: const Text('นับด้วยมือ'),
                      ),
                    Text(
                      _sample
                          ? 'ภาพตัวอย่าง 48 ตัว ใช้ทดลองขั้นตอน ไม่ใช่ผลจาก AI'
                          : _video
                          ? 'นับเฉพาะตัวที่เห็นในเฟรมที่เลือก'
                          : 'ตรวจภาพให้ชัด เห็นถาดครบ และลดเงาสะท้อนก่อนนับ',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                  const SizedBox(height: 8),
                  ExpansionTile(
                    key: const PageStorageKey('count-import-options'),
                    tilePadding: EdgeInsets.zero,
                    shape: const Border(),
                    collapsedShape: const Border(),
                    title: const Text(
                      'นำเข้าภาพอื่น (ทางเลือก)',
                      style: TextStyle(fontSize: 13),
                    ),
                    children: [
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: [
                          OutlinedButton.icon(
                            onPressed: _busy
                                ? null
                                : () => _pick(ImageSource.camera),
                            icon: const Icon(
                              Icons.photo_camera_outlined,
                              size: 18,
                            ),
                            label: const Text('กล้องมือถือ'),
                          ),
                          OutlinedButton.icon(
                            onPressed: _busy
                                ? null
                                : () => _pick(ImageSource.gallery),
                            icon: const Icon(Icons.image_outlined, size: 18),
                            label: const Text('เลือกภาพ'),
                          ),
                          OutlinedButton.icon(
                            onPressed: _busy
                                ? null
                                : () => _pick(ImageSource.gallery, video: true),
                            icon: const Icon(
                              Icons.video_library_outlined,
                              size: 18,
                            ),
                            label: const Text('เลือกคลิป'),
                          ),
                        ],
                      ),
                    ],
                  ),
                  TextButton(
                    onPressed: _busy ? null : _useSample,
                    child: const Text('ใช้ภาพตัวอย่าง'),
                  ),
                  if (_hasResult)
                    TextButton(
                      onPressed: () => setState(() => _workspace = true),
                      child: const Text('กลับไปตรวจผลนับ'),
                    ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 18),
        _history(state),
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
                      _steps(),
                      Row(
                        children: [
                          TextButton.icon(
                            onPressed: _busy
                                ? null
                                : () => setState(() => _workspace = false),
                            icon: const Icon(Icons.arrow_back_rounded),
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
                          SegmentedButton<bool>(
                            segments: const [
                              ButtonSegment(
                                value: false,
                                icon: Icon(Icons.zoom_in_rounded),
                                label: Text('ซูม/เลื่อน'),
                              ),
                              ButtonSegment(
                                value: true,
                                icon: Icon(Icons.touch_app_outlined),
                                label: Text('เพิ่ม/ลบจุด'),
                              ),
                            ],
                            selected: {_editing},
                            onSelectionChanged: _busy
                                ? null
                                : (s) => setState(() => _editing = s.first),
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
                            icon: const Icon(Icons.undo_rounded),
                          ),
                          PopupMenuButton<String>(
                            tooltip: 'เครื่องมือเพิ่มเติม',
                            enabled: !_busy,
                            icon: const Icon(Icons.more_horiz_rounded),
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
                      Text(
                        _editing
                            ? 'แตะพื้นที่ว่างเพื่อเพิ่ม แตะจุดเดิมเพื่อลบ'
                            : 'ใช้สองนิ้วซูม แล้วเลือกเพิ่ม/ลบจุดเพื่อตรวจแก้',
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
                            ? 'ผลตัวอย่างจำลอง · ไม่ใช่ผลจาก AI'
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
                          onPressed: () => showBatchDialog(
                            context,
                            ref.read(appControllerProvider.notifier),
                          ),
                          child: const Text('เริ่มรอบฟัก'),
                        ),
                      const SizedBox(height: 6),
                      const Text(
                        'นับเฉพาะตัวที่มองเห็นในภาพ ไม่ใช่จำนวนทั้งรอบฟัก',
                        style: TextStyle(fontSize: 12, color: AquaColors.muted),
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
                      _saved ? Icons.check_circle_outline : Icons.save_outlined,
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
  _PointsPainter(this.points);
  @override
  void paint(Canvas canvas, Size size) {
    for (final point in points) {
      final at = Offset(point.x * size.width, point.y * size.height);
      canvas.drawCircle(
        at,
        8,
        Paint()..color = AquaColors.teal.withValues(alpha: .1),
      );
      canvas.drawCircle(
        at,
        8,
        Paint()
          ..color = AquaColors.teal
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6,
      );
      canvas.drawCircle(at, 2, Paint()..color = AquaColors.teal);
    }
  }

  @override
  bool shouldRepaint(covariant _PointsPainter old) => old.points != points;
}
