import 'package:aqua_hatch/app/app.dart';
import 'package:aqua_hatch/core/controller.dart';
import 'package:aqua_hatch/core/local_store.dart';
import 'package:aqua_hatch/core/models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'widget_test.dart' show mountApp;

const addBatch = ValueKey('add-hatch-batch');
const saveBatch = ValueKey('save-hatch-batch');

class _WaitingForBoard extends AppController {
  @override
  AppState build() => super.build().copyWith(connected: false, busy: true);
}

Future<void> enterBatch(WidgetTester tester, String name) async {
  await tester.ensureVisible(find.byKey(addBatch));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(addBatch));
  await tester.pumpAndSettle();
  await tester.enterText(find.byType(TextFormField).first, name);
}

void main() {
  testWidgets('a round can be saved on a small screen with the keyboard up', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await mountApp(tester, size: const Size(320, 568), preferences: prefs);
    await enterBatch(tester, 'รอบทดสอบจอเล็ก');
    tester.view.viewInsets = const FakeViewPadding(bottom: 290);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpAndSettle();
    final eggs = find.byType(TextFormField).last;
    await tester.ensureVisible(eggs);
    await tester.enterText(eggs, '120');
    await tester.pumpAndSettle();
    final submit = find.byKey(saveBatch);
    expect(submit.hitTestable(), findsOneWidget);
    await tester.tap(submit);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(AlertDialog), findsNothing);
    expect(LocalStore(prefs).batch?.name, 'รอบทดสอบจอเล็ก');
    expect(LocalStore(prefs).batch?.eggs, 120);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('a new local round can replace a round while board is busy', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final store = LocalStore(await SharedPreferences.getInstance());
    final startedAt = DateTime(2026, 10, 1);
    await store.saveBatch(
      HatchBatch(id: 'old', name: 'รอบเดิม', startedAt: startedAt),
      store.connection,
    );
    await store.saveCounts([
      CountRecord(
        id: 'count-1',
        batchId: 'old',
        batchName: 'รอบเดิม',
        source: 'camera',
        method: 'manual',
        count: 42,
        at: startedAt,
        demo: false,
      ),
    ]);
    final container = ProviderContainer(
      overrides: [
        localStoreProvider.overrideWithValue(store),
        appControllerProvider.overrideWith(_WaitingForBoard.new),
      ],
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const AquaHatchApp(),
      ),
    );
    await tester.pumpAndSettle();
    await enterBatch(tester, 'รอบใหม่');
    await tester.tap(find.byKey(saveBatch));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(container.read(appControllerProvider).busy, isTrue);
    expect(store.batch?.name, 'รอบใหม่');
    expect(store.counts.single.batchId, 'old');
    expect(store.counts.single.count, 42);
    await tester.pumpWidget(const SizedBox());
    container.dispose();
    await tester.pump();
  });
}
