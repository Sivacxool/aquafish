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
  void _notifications(BuildContext context, AppState state) {
    final events = state.events.take(200).toList();
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (sheetContext) => SafeArea(
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
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
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
                                ? Icons.warning_amber_rounded
                                : Icons.check_circle_outline_rounded,
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
      ),
    );
  }

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
                      color: AquaColors.paper,
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
                                  'AquaHatch',
                                  style: TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 1,
                                  ),
                                ),
                              ],
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
                                      ? AquaColors.lime
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
                        height: 60,
                        padding: EdgeInsets.symmetric(
                          horizontal: desktop ? 32 : 20,
                        ),
                        decoration: const BoxDecoration(
                          color: AquaColors.paper,
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
                            const Expanded(
                              child: Text(
                                'AquaHatch',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 19,
                                ),
                              ),
                            ),
                            if (shell.currentIndex != 0 &&
                                !state.connection.demo)
                              Pill(
                                state.fresh ? 'ออนไลน์' : 'ออฟไลน์',
                                color: state.fresh
                                    ? AquaColors.teal
                                    : AquaColors.orange,
                                icon: Icons.circle,
                              ),
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
                  ).scale(68).clamp(68, 132),
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
