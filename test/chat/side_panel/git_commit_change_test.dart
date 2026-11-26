import 'package:baocode/chat/side_panel/file_open.dart';
import 'package:baocode/chat/side_panel/git_changes.dart';
import 'package:baocode/chat/side_panel/side_panel_controller.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../ide/git/fake_git.dart';

void main() {
  test("a commit's change to a file opens as its diff, blamed at it", () async {
    final commit = 'c' * 40;
    final fake = FakeGit('/repo')
      ..show[commit] = 'M\x00a.dart\x00'
      ..show['$commit^:a.dart'] = 'one\n'
      ..show['$commit:a.dart'] = 'one\ntwo\n';
    final git = fake.repository();
    addTearDown(git.dispose);

    final request = await gitCommitChangeRequest(git, '/repo/a.dart', commit);
    expect(request, isNotNull);
    expect(request!.path, '/repo/a.dart');
    expect(request.diff, isTrue);
    expect(request.commitId, commit);
    expect(await request.original!(), 'one\n');
    expect(await request.modified!(), 'one\ntwo\n');
  });

  test('a commit that did not change the file opens nothing', () async {
    final commit = 'c' * 40;
    final fake = FakeGit('/repo')..show[commit] = 'M\x00b.dart\x00';
    final git = fake.repository();
    addTearDown(git.dispose);

    expect(await gitCommitChangeRequest(git, '/repo/a.dart', commit), isNull);
  });

  test(
    "a commit's list naming the file otherwise still opens its diff",
    () async {
      final commit = 'c' * 40;
      final fake = FakeGit('/repo')
        ..show[commit] = ''
        ..show['$commit^:a.dart'] = 'one\n'
        ..show['$commit:a.dart'] = 'one\ntwo\n';
      final git = fake.repository();
      addTearDown(git.dispose);

      final request = await gitCommitChangeRequest(git, '/repo/a.dart', commit);
      expect(request, isNotNull);
      expect(request!.path, '/repo/a.dart');
      expect(request.commitId, commit);
      expect(await request.original!(), 'one\n');
      expect(await request.modified!(), 'one\ntwo\n');
    },
  );

  test("a commit's diff keeps a tab of its own, beside the file's changes", () {
    final panel = AgentSidePanel();
    addTearDown(panel.dispose);
    final conversation = Object();
    final tabs = panel.tabsOf(conversation);
    panel.open(conversation, const FileOpenRequest('/p/a.dart', diff: true));
    final changes = tabs.activeDiff;
    expect(changes, isNotNull);

    panel.open(
      conversation,
      const FileOpenRequest('/p/a.dart', diff: true, commitId: 'abc'),
    );
    final commit = tabs.activeDiff;
    expect(commit, isNot(same(changes)));
    expect(tabs.diffs, hasLength(2));

    // The file's changes opened again: its tab, the commit's kept.
    panel.open(conversation, const FileOpenRequest('/p/a.dart', diff: true));
    expect(tabs.activeDiff, same(changes));
    expect(tabs.diffs, hasLength(2));
  });
}
