import 'package:bao_editor/monaco/flutter/editor_surface.dart';
import 'package:baocode/chat/side_panel/file_open.dart';
import 'package:baocode/chat/side_panel/file_preview.dart';
import 'package:baocode/ide/file_service.dart';
import 'package:baocode/ide/ide_hover.dart' show ideHoverDelay;
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../ide/git/fake_git.dart';
import '../../ide/workbench/fake_files.dart';

class _Files with ReadWriteOnlyFiles implements IdeFileService {
  _Files(this.contents);

  final Map<String, String> contents;

  @override
  Future<List<IdeFile>> list(String directory) async => [];

  @override
  Future<String> read(String path, {bool force = false}) async =>
      contents[path]!;

  @override
  Future<void> write(String path, String text, {String? expectedText}) async =>
      contents[path] = text;
}

/// `one` and `two` by Ada, `three` by Grace.
String _blame() => [
  gitBlameEntry('a' * 40, 1, 2, author: 'Ada', summary: 'Initial commit'),
  gitBlameEntry('b' * 40, 3, 1, author: 'Grace', summary: 'Third line'),
].join();

void main() {
  late FakeGit git;

  setUp(() {
    git = FakeGit('/repo')
      ..refs['HEAD'] = 'f' * 40
      ..blame['a.dart'] = _blame();
  });

  testWidgets('the editor shows the caret\'s line\'s blame after it', (
    tester,
  ) async {
    final repository = git.repository();
    addTearDown(repository.dispose);
    final shown = <(String, String)>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FilePreview(
            request: FileOpenRequest('/repo/a.dart'),
            files: _Files({'/repo/a.dart': 'one\ntwo\nthree\n'}),
            git: repository,
            onShowCommit: (_, path, commit) => shown.add((path, commit)),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Nothing yet: the caret is at the start, where it was left.
    expect(
      tester
          .widget<EditorSurface>(find.byType(EditorSurface))
          .decorations
          .where((decoration) => decoration.afterText != null),
      isEmpty,
    );

    tester
        .widget<EditorSurface>(find.byType(EditorSurface))
        .controller
        .select(4, 4);
    await tester.pumpAndSettle();

    final blame = [
      for (final decoration
          in tester
              .widget<EditorSurface>(find.byType(EditorSurface))
              .decorations)
        ?decoration.afterText,
    ];
    expect(blame, hasLength(1));
    expect(blame.single, contains('Ada'));

    // A press on it shows its commit's details, in the panel.
    final surface = find.byType(EditorSurface);
    final view = tester.state(surface) as EditorSurfaceView;
    final end = tester
        .widget<EditorSurface>(surface)
        .controller
        .document
        .snapshot
        .contentEnds[1];
    final caret = view.caretRectAt(end)!;
    await tester.tapAt(
      tester
          .renderObject<RenderBox>(surface)
          .localToGlobal(caret.center + const Offset(60, 0)),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('ada@example.com'), findsOneWidget);

    // Its hash shows the commit's changes.
    await tester.tap(find.text('aaaaaaaa'));
    await tester.pumpAndSettle();
    expect(shown, [('/repo/a.dart', 'a' * 40)]);
    expect(find.textContaining('ada@example.com'), findsNothing);
  });

  testWidgets('a read-only preview shows it on the line hovered', (
    tester,
  ) async {
    final repository = git.repository();
    addTearDown(repository.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FilePreview(
            request: FileOpenRequest('/repo/a.dart', readOnly: true),
            files: _Files({'/repo/a.dart': 'one\ntwo\nthree\n'}),
            git: repository,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Ada'), findsNothing);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(find.text('two')));
    await tester.pumpAndSettle();

    expect(find.textContaining('Ada'), findsOneWidget);
    expect(find.textContaining('Grace'), findsNothing);
  });

  testWidgets('the card stays as the pointer goes from the blame to it', (
    tester,
  ) async {
    final repository = git.repository();
    addTearDown(repository.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FilePreview(
            request: FileOpenRequest('/repo/a.dart'),
            files: _Files({'/repo/a.dart': 'one\ntwo\nthree\n'}),
            git: repository,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final surface = find.byType(EditorSurface);
    final editor = tester.widget<EditorSurface>(surface).controller;
    editor.select(4, 4);
    await tester.pumpAndSettle();

    final view = tester.state(surface) as EditorSurfaceView;
    final caret = view.caretRectAt(editor.document.snapshot.contentEnds[1])!;
    final blame = tester
        .renderObject<RenderBox>(surface)
        .localToGlobal(caret.center + const Offset(60, 0));
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(blame);
    await tester.pump(ideHoverDelay + const Duration(milliseconds: 50));
    expect(find.textContaining('ada@example.com'), findsOneWidget);

    // Onto the card: it is not taken away on the way.
    await mouse.moveTo(blame + const Offset(40, 40));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.textContaining('ada@example.com'), findsOneWidget);
  });
}
