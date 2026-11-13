import '../core/motion.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/controller.dart';
import '../core/local_store.dart';
import 'app.dart';
import 'brand.dart';
import 'theme.dart';

class AppBootstrap extends StatefulWidget {
  const AppBootstrap({super.key, this.loadPreferences});
  final Future<SharedPreferences> Function()? loadPreferences;
  @override
  State<AppBootstrap> createState() => _AppBootstrapState();
}

class _AppBootstrapState extends State<AppBootstrap> {
  SharedPreferences? _preferences;
  bool _introComplete = false, _failed = false;
  Timer? _intro;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final preferences =
          await (widget.loadPreferences ?? SharedPreferences.getInstance)()
              .timeout(const Duration(seconds: 12));
      if (mounted) {
        setState(() {
          _preferences = preferences;
          _failed = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // One cold-launch intro while storage loads; never wait for Wi-Fi here.
    _intro ??= Timer(
      MediaQueryData.fromView(View.of(context)).disableAnimations
          ? Duration.zero
          : const Duration(milliseconds: 1600),
      () {
        if (mounted) setState(() => _introComplete = true);
      },
    );
  }

  @override
  void dispose() {
    _intro?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_preferences != null && _introComplete) {
      return ProviderScope(
        overrides: [
          localStoreProvider.overrideWithValue(LocalStore(_preferences!)),
        ],
        child: const AquaHatchApp(),
      );
    }
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      home: Scaffold(
        backgroundColor: AquaColors.deep,
        body: SafeArea(
          child: SizedBox.expand(
            child: Column(
              children: [
                const Spacer(flex: 3),
                const CatfishMark(
                  key: ValueKey('startup-animation'),
                  size: 180,
                  animate: true,
                ),
                const SizedBox(height: 24),
                const Text(
                  'Smart Catfish',
                  style: TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.w500,
                    letterSpacing: -1,
                    color: AquaColors.paper,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'S Y S T E M',
                  style: TextStyle(fontSize: 12, color: AquaColors.lime),
                ),
                const Spacer(flex: 2),
                if (_failed) ...[
                  const Text(
                    'เปิดข้อมูลไม่สำเร็จ',
                    style: TextStyle(color: AquaColors.paper),
                  ),
                  TextButton(
                    onPressed: () {
                      setState(() => _failed = false);
                      _load();
                    },
                    child: const Text(
                      'ลองอีกครั้ง',
                      style: TextStyle(color: AquaColors.lime),
                    ),
                  ),
                ] else
                  const AquaLoader(
                    label: 'กำลังเปิดแอป',
                    color: AquaColors.lime,
                  ),
                const SizedBox(height: 48),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
