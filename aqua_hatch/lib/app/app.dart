import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../core/controller.dart';
import '../core/ui.dart';
import '../features/dashboard.dart';
import '../features/controls.dart';
import '../features/counting.dart';
import '../features/settings.dart';
import 'theme.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final router = GoRouter(
    initialLocation: '/dashboard',
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => AppShell(shell: shell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/dashboard',
                builder: (c, s) => const DashboardScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/controls',
                builder: (c, s) => const ControlsScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/counting',
                builder: (c, s) => const CountingScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/settings',
                builder: (c, s) => const SettingsScreen(),
              ),
            ],
          ),
        ],
      ),
    ],
  );
  ref.onDispose(router.dispose);
  return router;
});

class AquaHatchApp extends ConsumerWidget {
  const AquaHatchApp({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => MaterialApp.router(
    title: 'Aqua Hatch · เครื่องฟักไข่ปลาดุก',
    debugShowCheckedModeBanner: false,
    theme: buildTheme(),
    locale: const Locale('th', 'TH'),
    supportedLocales: const [Locale('th', 'TH')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    routerConfig: ref.watch(routerProvider),
  );
}

class AppShell extends ConsumerWidget {
  final StatefulNavigationShell shell;
  const AppShell({super.key, required this.shell});
  static const labels = ['ภาพรวม', 'ควบคุมเครื่อง', 'นับลูกปลา', 'ตั้งค่า'];
  static const icons = [
    Icons.space_dashboard_outlined,
    Icons.tune_rounded,
    Icons.center_focus_strong_rounded,
    Icons.settings_outlined,
  ];
  void _notifications(BuildContext context, AppState state) =>
      showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (context) => SafeArea(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SectionHeading('กิจกรรมและการแจ้งเตือน'),
                  if (state.events.isEmpty) const Text('ยังไม่มีกิจกรรม'),
                  ...state.events
                      .take(200)
                      .map(
                        (e) => ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(
                            e.warning
                                ? Icons.warning_amber_rounded
                                : Icons.check_circle_outline_rounded,
                            color: e.warning
                                ? AquaColors.orange
                                : AquaColors.teal,
                          ),
                          title: Text(e.message),
                          subtitle: Text(shortTime(e.at)),
                        ),
                      ),
                ],
              ),
            ),
          ),
        ),
      );
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(appControllerProvider);
    return LayoutBuilder(
      builder: (context, constraints) {
        final desktop = constraints.maxWidth >= 1000;
        return Scaffold(
          body: Row(
            children: [
              if (desktop)
                SizedBox(
                  width: 240,
                  child: Container(
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      border: Border(right: BorderSide(color: AquaColors.line)),
                    ),
                    child: SafeArea(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 10),
                            const Row(
                              children: [
                                FishIllustration(size: 47),
                                SizedBox(width: 12),
                                Text(
                                  'AQUA HATCH',
                                  style: TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 1,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 9),
                            const Text(
                              'ระบบฟักไข่ปลาดุกอัจฉริยะ',
                              style: TextStyle(
                                fontSize: 12,
                                color: AquaColors.muted,
                              ),
                            ),
                            const SizedBox(height: 42),
                            const Text(
                              'พื้นที่ทำงาน',
                              style: TextStyle(
                                fontSize: 12,
                                color: AquaColors.muted,
                              ),
                            ),
                            const SizedBox(height: 16),
                            ...List.generate(
                              4,
                              (i) => Padding(
                                padding: const EdgeInsets.only(bottom: 9),
                                child: Material(
                                  color: shell.currentIndex == i
                                      ? const Color(0xFFE9F3F8)
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(13),
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(13),
                                    onTap: () => shell.goBranch(i),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 15,
                                        vertical: 15,
                                      ),
                                      child: Row(
                                        children: [
                                          Icon(
                                            icons[i],
                                            size: 21,
                                            color: shell.currentIndex == i
                                                ? AquaColors.blue
                                                : AquaColors.muted,
                                          ),
                                          const SizedBox(width: 13),
                                          Text(
                                            labels[i],
                                            style: TextStyle(
                                              fontWeight:
                                                  shell.currentIndex == i
                                                  ? FontWeight.w700
                                                  : FontWeight.w500,
                                              color: shell.currentIndex == i
                                                  ? AquaColors.blue
                                                  : AquaColors.muted,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const Spacer(),
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(18),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF0F8FA),
                                borderRadius: BorderRadius.circular(18),
                              ),
                              child: const Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  FishIllustration(
                                    size: 55,
                                    color: AquaColors.teal,
                                  ),
                                  SizedBox(height: 12),
                                  Text(
                                    'ดูแลชีวิตเล็ก ๆ\nให้เติบโตไปด้วยกัน',
                                    style: TextStyle(
                                      fontSize: 12,
                                      height: 1.8,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  SizedBox(height: 10),
                                  Text(
                                    'Aqua Hatch · v0.6.0',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: AquaColors.muted,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 12),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              Expanded(
                child: SafeArea(
                  bottom: false,
                  child: Column(
                    children: [
                      Container(
                        height: 64,
                        padding: EdgeInsets.symmetric(
                          horizontal: desktop ? 32 : 20,
                        ),
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          border: Border(
                            bottom: BorderSide(color: AquaColors.line),
                          ),
                        ),
                        child: Row(
                          children: [
                            if (!desktop) ...[
                              const FishIllustration(size: 32),
                              const SizedBox(width: 10),
                            ],
                            Expanded(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    desktop
                                        ? 'เครื่องฟัก · โถ 01'
                                        : 'AQUA HATCH',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 14,
                                    ),
                                  ),
                                  Text(
                                    (state.connection.demo ||
                                            state.telemetry?.simulated == true)
                                        ? 'พื้นที่ทดลอง · ข้อมูลจำลอง'
                                        : state.connection.deviceId,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: AquaColors.muted,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Pill(
                              (state.connection.demo ||
                                      state.telemetry?.simulated == true)
                                  ? 'โหมดทดลอง'
                                  : state.fresh
                                  ? 'เชื่อมต่อแล้ว'
                                  : 'รอเชื่อมต่อ',
                              color:
                                  (state.connection.demo ||
                                      state.telemetry?.simulated == true)
                                  ? AquaColors.blue
                                  : state.fresh
                                  ? AquaColors.teal
                                  : AquaColors.orange,
                              icon:
                                  (state.connection.demo ||
                                      state.telemetry?.simulated == true)
                                  ? Icons.science_outlined
                                  : Icons.circle,
                            ),
                            const SizedBox(width: 10),
                            IconButton(
                              tooltip: 'กิจกรรมและการแจ้งเตือน',
                              onPressed: () {
                                _notifications(context, state);
                                ref
                                    .read(appControllerProvider.notifier)
                                    .acknowledgeEvents();
                              },
                              icon: Badge(
                                isLabelVisible: state.events.any(
                                  (e) => e.warning && !e.acknowledged,
                                ),
                                label: Text(
                                  state.events
                                      .where(
                                        (e) => e.warning && !e.acknowledged,
                                      )
                                      .length
                                      .toString(),
                                ),
                                child: const Icon(
                                  Icons.notifications_none_rounded,
                                  color: AquaColors.navy,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Expanded(child: shell),
                    ],
                  ),
                ),
              ),
            ],
          ),
          bottomNavigationBar: desktop
              ? null
              : NavigationBar(
                  height: MediaQuery.textScalerOf(
                    context,
                  ).scale(76).clamp(76, 140),
                  selectedIndex: shell.currentIndex,
                  onDestinationSelected: (i) => shell.goBranch(i),
                  destinations: List.generate(
                    4,
                    (i) => NavigationDestination(
                      icon: Icon(icons[i]),
                      label: i == 1 ? 'ควบคุม' : labels[i],
                    ),
                  ),
                ),
        );
      },
    );
  }
}
