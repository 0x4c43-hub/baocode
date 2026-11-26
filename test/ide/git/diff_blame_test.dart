import 'package:bao_editor/monaco/flutter/editor_surface.dart';
import 'package:baocode/ide/ide_code_diff.dart';
import 'package:baocode/ide/ide_hover.dart' show ideHoverDelay;
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_git.dart';

/// `one` by Ada, `TWO` by Grace.
String _blame() => [
  gitBlameEntry('a' * 40, 1, 1, author: 'Ada', summary: 'Initial commit'),
  gitBlameEntry('b' * 40, 2, 1, author: 'Grace', summary: 'Second line'),
].join();

void main() {
  late FakeGit git;

  setUp(() {
    git = FakeGit('/repo')
      ..refs['HEAD'] = 'f' * 40
      ..blame['a.dart'] = _blame();
  });

  testWidgets('a diff shows the caret line\'s blame after it', (tester) async {
    final repository = git.repository();
    addTearDown(repository.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: IdeCodeDiff(
            path: '/repo/a.dart',
            original: 'one\ntwo\n',
            modified: 'one\nTWO\n',
            git: repository,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final modified = tester
        .widgetList<EditorSurface>(find.byType(EditorSurface))
        .firstWhere(
          (surface) => surface.controller.document.text == 'one\nTWO\n',
        )
        .controller;

    // The first line's: the caret there.
    modified.select(0, 0);
    await tester.pumpAndSettle();
    final blame = [
      for (final surface in tester.widgetList<EditorSurface>(
        find.byType(EditorSurface),
      ))
        for (final decoration in surface.decorations) ?decoration.afterText,
    ];
    expect(blame, hasLength(1));
    expect(blame.single, contains('Ada'));

    // The second line's: the caret moved there.
    modified.select(5, 5);
    await tester.pumpAndSettle();
    final moved = [
      for (final surface in tester.widgetList<EditorSurface>(
        find.byType(EditorSurface),
      ))
        for (final decoration in surface.decorations) ?decoration.afterText,
    ];
    expect(moved, hasLength(1));
    expect(moved.single, contains('Grace'));
  });

  testWidgets('a diff shows the blame of the line the pointer is over', (
    tester,
  ) async {
    final repository = git.repository();
    addTearDown(repository.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: IdeCodeDiff(
            path: '/repo/a.dart',
            original: 'one\ntwo\n',
            modified: 'one\nTWO\n',
            git: repository,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final surface = find.byType(EditorSurface).first;
    final view = tester.state(surface) as EditorSurfaceView;
    final box = tester.renderObject<RenderBox>(surface);
    final caret = view.caretRectAt(7)!;
    final pointer = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(pointer.removePointer);
    await pointer.addPointer(location: Offset.zero);
    await pointer.moveTo(box.localToGlobal(caret.center));
    await tester.pump();

    final blame = [
      for (final surface in tester.widgetList<EditorSurface>(
        find.byType(EditorSurface),
      ))
        for (final decoration in surface.decorations) ?decoration.afterText,
    ];
    expect(blame, hasLength(1));
    expect(blame.single, contains('Grace'));

    // Rested on the line, its card shows too.
    await tester.pump(ideHoverDelay + const Duration(milliseconds: 100));
    expect(find.textContaining('grace@example.com'), findsOneWidget);
  });

  testWidgets("a commit's diff shows the original side's blame too", (
    tester,
  ) async {
    final repository = git.repository();
    addTearDown(repository.dispose);
    final shown = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: IdeCodeDiff(
            path: '/repo/a.dart',
            original: 'one\ntwo\n',
            modified: 'one\nTWO\n',
            git: repository,
            commitId: 'c' * 40,
            sideBySide: true,
            onShowCommit: shown.add,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final original = tester
        .widgetList<EditorSurface>(find.byType(EditorSurface))
        .firstWhere(
          (surface) => surface.controller.document.text == 'one\ntwo\n',
        );
    final surface = find.byWidgetPredicate(
      (widget) =>
          widget is EditorSurface &&
          identical(widget.controller, original.controller),
    );
    final view = tester.state(surface) as EditorSurfaceView;
    final box = tester.renderObject<RenderBox>(surface);
    final caret = view.caretRectAt(7)!;
    final pointer = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(pointer.removePointer);
    await pointer.addPointer(location: Offset.zero);
    await pointer.moveTo(box.localToGlobal(caret.center));
    await tester.pump();

    final blame = [
      for (final decoration
          in tester.widget<EditorSurface>(surface).decorations)
        ?decoration.afterText,
    ];
    expect(blame, hasLength(1));
    expect(blame.single, contains('Grace'));

    // Its hash shows the commit.
    await tester.pump(ideHoverDelay + const Duration(milliseconds: 100));
    await tester.tap(find.text('b' * 8));
    await tester.pumpAndSettle();
    expect(shown, ['b' * 40]);
  });
}
