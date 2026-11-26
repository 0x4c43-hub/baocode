import '../../ide/file_service.dart';
import '../../ide/git/git_change_editor.dart';
import '../../ide/git/git_model.dart';
import '../../ide/git/git_repository.dart';
import '../../ide/git/git_service.dart' show IdeGitCommitChange;
import 'file_open.dart';

/// [resource]'s changes, as the IDE's Source Control opens them (see
/// [IdeGitChangeEditor]): its text at HEAD or in the index against the
/// index's or the file's; an added file's against nothing, a deleted
/// one's text against nothing.
FileOpenRequest gitChangeRequest(
  IdeGitRepository git,
  IdeGitState state,
  IdeGitResource resource,
) {
  final editor = IdeGitChangeEditor.of(
    resource,
    staged: state.group(IdeGitGroup.staged),
  );
  Future<String> Function() show(IdeGitSide side) =>
      () => git.service.show(side.ref!, side.path);
  final (left, right) = (editor.left, editor.right);
  // Deleted: HEAD's text, and no file.
  if (left == null && right != null && right.ref == 'HEAD') {
    return FileOpenRequest(
      resource.path,
      diff: true,
      original: show(right),
      modified: () async => throw IdeFileNotFoundException(resource.path),
    );
  }
  return FileOpenRequest(
    resource.path,
    diff: true,
    // Not there (before the first commit): none before it.
    original: left == null
        ? () async => ''
        : () => show(left)().catchError((Object _) => ''),
    modified: right == null || right.isFile ? null : show(right),
  );
}

/// [commit]'s changes to the file at [path] (absolute, on the project's
/// host), as the Git log shows them: its text in the commit against its
/// first parent's; none where the commit did not change that file.
///
/// The file as it is now is named, so the tab is the file's, its blame the
/// commit's ([FileOpenRequest.commitId]).
Future<FileOpenRequest?> gitCommitChangeRequest(
  IdeGitRepository git,
  String path,
  String commit,
) async {
  final paths = git.service.pathContext;
  final target = paths.normalize(path);
  Future<String> show(String ref, String path) =>
      git.service.show(ref, path).catchError((Object _) => '');
  IdeGitCommitChange? change;
  try {
    change = (await git.commitChanges(commit)).where((change) {
      if (paths.normalize(change.path) == target) return true;
      final before = change.originalPath;
      return before != null && paths.normalize(before) == target;
    }).firstOrNull;
  } catch (_) {
    change = null;
  }
  final found = change;
  if (found == null) {
    // Not named as this repository spells it (a worktree's, a link's), or
    // another repository's list: the file's text in the commit tells
    // whether there is any to show.
    late final String modified;
    try {
      modified = await git.service.show(commit, path);
    } catch (_) {
      return null;
    }
    final original = await git.service
        .show('$commit^', path)
        .then<String?>((text) => text, onError: (Object _) => null);
    return FileOpenRequest(
      path,
      diff: true,
      commitId: commit,
      // Its first parent's; none for the first commit.
      original: () async => original ?? '',
      modified: () async => modified,
    );
  }
  return FileOpenRequest(
    found.path,
    diff: true,
    commitId: commit,
    // Its first parent's; none for the first commit.
    original: found.status == 'A'
        ? () async => ''
        : () => show('$commit^', found.originalPath ?? found.path),
    modified: found.status == 'D'
        ? () async => throw IdeFileNotFoundException(found.path)
        : () => show(commit, found.path),
  );
}
