import 'package:aqua_hatch/app/icons.dart';
import 'dart:async';
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
import 'brand.dart';

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

class AquaHatchApp extends ConsumerStatefulWidget {
  const AquaHatchApp({super.key});

  @override
  ConsumerState<AquaHatchApp> createState() => _AquaHatchAppState();
}

class _AquaHatchAppState extends ConsumerState<AquaHatchApp> {
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(
      onResume: () => unawaited(
        ref.read(appControllerProvider.notifier).refreshLocalConnection(),
      ),
    );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp.router(
    title: 'Smart Catfish System',
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
    PhosphorIconsRegular.squaresFour,
    PhosphorIconsRegular.slidersHorizontal,
    PhosphorIconsRegular.scan,
    PhosphorIconsRegular.gearSix,
  ];
  void _notifications(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) => Consumer(
        builder: (context, ref, _) {
          final events = ref.watch(
            appControllerProvider.select((state) => state.events),
          );
          return SafeArea(
            top: false,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(sheetContext).height * .82,
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 16, 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Expanded(
                          child: SectionHeading('กิจกรรมและการแจ้งเตือน'),
                        ),
                        IconButton(
                          tooltip: 'ปิดการแจ้งเตือน',
                          onPressed: () => Navigator.of(sheetContext).pop(),
                          icon: const Icon(PhosphorIconsRegular.x),
                        ),
                      ],
                    ),
                    if (events.isNotEmpty)
                      TextButton.icon(
                        icon: const Icon(PhosphorIconsRegular.trash),
                        label: const Text('ล้างการแจ้งเตือน'),
                        onPressed: () async {
                          final controller = ref.read(
                            appControllerProvider.notifier,
                          );
                          if (!await confirmClear(
                                context,
                                'ล้างการแจ้งเตือน?',
                                'ลบรายการแจ้งเตือนของเครื่องนี้ในมือถือ',
                              ) ||
                              !context.mounted) {
                            return;
                          }
                          final saved = await controller.clearEvents();
                          if (!saved && context.mounted) {
                            showFeedback(context, 'ล้างการแจ้งเตือนไม่สำเร็จ');
                          }
                        },
                      ),
                    if (events.isEmpty)
                      const Text('ยังไม่มีกิจกรรม')
                    else
                      Flexible(
                        child: ListView.builder(
                          key: const ValueKey('notification-events'),
                          shrinkWrap: true,
                          itemCount: events.length,
                          itemBuilder: (context, index) {
                            final event = events[index];
                            return ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: Icon(
                                event.warning
                                    ? PhosphorIconsRegular.warning
                                    : PhosphorIconsRegular.checkCircle,
                                color: event.warning
                                    ? AquaColors.orange
                                    : AquaColors.teal,
                              ),
                              title: Text(event.message),
                              subtitle: Text(shortTime(event.at)),
                            );
                          },
                        ),
                      ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(appControllerProvider);
    final simulated =
        state.connection.demo || state.telemetry?.simulated == true;
    final reduced = MediaQuery.disableAnimationsOf(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final desktop = constraints.maxWidth >= 1000;
        return Scaffold(
          body: SafeArea(
            bottom: false,
            child: Row(
              children: [
                if (desktop)
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: NavigationRail(
                      backgroundColor: AquaColors.sage,
                      extended: true,
                      leading: const Padding(
                        padding: EdgeInsets.all(20),
                        child: CatfishMark(size: 70, color: AquaColors.blue),
                      ),
                      selectedIndex: shell.currentIndex,
                      onDestinationSelected: (i) => shell.goBranch(i),
                      destinations: List.generate(
                        4,
                        (i) => NavigationRailDestination(
                          icon: Icon(icons[i]),
                          label: Text(labels[i]),
                        ),
                      ),
                    ),
                  ),
                Expanded(
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 4, 12, 0),
                        child: Row(
                          children: [
                            const CatfishMark(size: 36, color: AquaColors.blue),
                            const SizedBox(width: 8),
                            const Expanded(
                              child: Text(
                                'Smart Catfish',
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 16,
                                  letterSpacing: -.5,
                                ),
                              ),
                            ),
                            if (simulated)
                              const Pill(
                                'โหมดทดลอง',
                                icon: PhosphorIconsRegular.flask,
                              ),
                            IconButton(
                              tooltip: 'กิจกรรมและการแจ้งเตือน',
                              onPressed: () {
                                _notifications(context);
                                ref
                                    .read(appControllerProvider.notifier)
                                    .acknowledgeEvents();
                              },
                              icon: Badge(
                                isLabelVisible: state.events.any(
                                  (e) => e.warning && !e.acknowledged,
                                ),
                                child: const Icon(PhosphorIconsRegular.bell),
                              ),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: TweenAnimationBuilder<double>(
                          tween: Tween(begin: reduced ? 1 : 0, end: 1),
                          duration: reduced ? Duration.zero : AquaMotion.move,
                          curve: AquaMotion.curve,
                          child: shell,
                          builder: (context, value, child) => Opacity(
                            opacity: value,
                            child: Transform.translate(
                              offset: Offset(0, 8 * (1 - value)),
                              child: child,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          bottomNavigationBar: desktop
              ? null
              : SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: NavigationBarTheme(
                        data: NavigationBarThemeData(
                          backgroundColor: AquaColors.paper,
                          indicatorColor: AquaColors.lime,
                          iconTheme: WidgetStateProperty.resolveWith(
                            (states) => IconThemeData(
                              color: states.contains(WidgetState.selected)
                                  ? AquaColors.deep
                                  : AquaColors.muted,
                            ),
                          ),
                          labelTextStyle: const WidgetStatePropertyAll(
                            TextStyle(
                              fontFamily: 'NotoSansThai',
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AquaColors.navy,
                            ),
                          ),
                        ),
                        child: NavigationBar(
                          height: MediaQuery.textScalerOf(
                            context,
                          ).scale(66).clamp(66, 120),
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
                      ),
                    ),
                  ),
                ),
        );
      },
    );
  }
}
