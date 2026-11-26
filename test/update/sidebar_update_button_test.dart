import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:baocode/l10n/l10n.dart';
import 'package:baocode/sidebar/sidebar.dart';
import 'package:baocode/update/source_update_controller.dart';
import 'package:baocode/update/update_service.dart';
import 'package:baocode/update/version.dart';
import 'package:baocode/workspace/workspace.dart';

import 'update_fakes.dart';

void main() {
  final l10n = englishLocalizations;

  Future<void> show(
    WidgetTester tester,
    UpdateService service,
    VoidCallback onUpdate,
  ) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 260,
            child: Sidebar(
              workspace: Workspace.mock(),
              onCollapse: () {},
              onOpenSettings: () {},
              updates: service,
              onUpdate: onUpdate,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  Finder update() => find.text(l10n.updateButton);

  testWidgets('Update shows beside the gear while an update waits', (
    tester,
  ) async {
    final backend = FakeBackend(manifestOf('1.2.0'));
    final service = serviceOf(backend);
    var updates = 0;
    await show(tester, service, () => updates++);
    expect(update(), findsNothing);

    await tester.runAsync(() async {
      await service.check(manual: true);
      await service.download();
    });
    await tester.pump();
    expect(update(), findsOneWidget);

    await tester.tap(update());
    expect(updates, 1);

    // Skipped: not offered again, but still there to install.
    service.skip(service.release!);
    await tester.pump();
    expect(update(), findsOneWidget);

    // Up to date: it goes.
    await tester.runAsync(() async {
      backend.manifest = manifestOf('1.0.0+1');
      await service.check(manual: true);
    });
    await tester.pump();
    expect(update(), findsNothing);
    service.dispose();
  });

  testWidgets('a custom build shows it while its sources have a version', (
    tester,
  ) async {
    final data = Directory.systemTemp.createTempSync('baocode-sidebar');
    addTearDown(() => data.deleteSync(recursive: true));
    final source = SourceUpdateController(
      sourceDir: data.path,
      logPath: '${data.path}/update.log',
    )..localVersion = AppVersion.parse('2.0.6+39');
    source.sourceVersion = AppVersion.parse('2.0.6+39');
    var updates = 0;
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 260,
            child: Sidebar(
              workspace: Workspace.mock(),
              onCollapse: () {},
              onOpenSettings: () {},
              sourceUpdates: source,
              onSourceUpdate: () => updates++,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(update(), findsNothing);

    source.upstreamVersion = AppVersion.parse('2.0.7+40');
    source.notifyListeners();
    await tester.pump();
    expect(update(), findsOneWidget);

    await tester.tap(update());
    expect(updates, 1);

    // The same version again: it goes.
    source.sourceVersion = AppVersion.parse('2.0.7+40');
    source.localVersion = AppVersion.parse('2.0.7+40');
    source.notifyListeners();
    await tester.pump();
    expect(update(), findsNothing);

    // Merged but not installed: it is there to build that version.
    source.localVersion = AppVersion.parse('2.0.6+39');
    source.notifyListeners();
    await tester.pump();
    expect(update(), findsOneWidget);
    source.dispose();
  });
}
