// The actions behind the header's Git menu (see
// workspace/window_header/git_menu.dart), built from the workbench's current
// repository. Operations go through IdeGitRepository, so the status, the
// sync indicator and the refresh that follows are the same as the Source
// Control view's buttons and the palette's Git commands.

import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../l10n/l10n.dart';
import '../../workspace/window_header/git_menu.dart';
import '../file_service.dart' show IdeFileService;
import '../ide_dialog.dart';
import '../ide_notifications.dart';
import '../ide_quick_input.dart';
import '../services/scm_service.dart';
import '../workbench/views.dart' show IdeSideView;
import 'git_branch_actions.dart' show IdeGitBranchActions, IdeGitBranchHost;
import 'git_branch_tree.dart' show IdeGitFavoriteBranches;
import 'git_model.dart' show IdeGitRefKind;
import 'git_repository.dart';
import 'ide_git_log_view.dart' show IdeGitDiffFile;
import 'ide_scm_view.dart' show IdeScmSession;
import 'ide_git_stash_view.dart' show ideGitStashChanges;

/// Makes the Git menu's actions from the workbench's Git service. What has
/// no repository has no Git menu at all.
GitMenuActions ideGitMenuActions({
  required BuildContext context,
  required ScmService scm,
  required VoidCallback clone,
}) {
  final git = scm.git;
  if (git == null) return const GitMenuActions();
  final l10n = context.l10n;
  final host = scm.host;
  final notifications = scm.workspace.notifications;

  void run(Future<void> Function() operation) =>
      unawaited(operation().catchError(host.report));

  Future<String?> pick(String placeholder, List<String> choices) {
    final completer = Completer<String?>();
    host.showQuickModel(
      IdeQuickPick(
        placeholder: placeholder,
        items: [for (final choice in choices) IdeQuickPickItem(label: choice)],
        onDidAccept: (item) {
          if (!completer.isCompleted) completer.complete(item?.label);
        },
        onDidHide: () {
          if (!completer.isCompleted) completer.complete(null);
        },
      ),
    );
    return completer.future;
  }

  Future<(String, String)?> pickRemoteAndBranch() async {
    final remotes = await git.service.remotes();
    if (remotes.isEmpty) {
      notifications.notify(IdeSeverity.warning, l10n.gitMenuNoRemote);
      return null;
    }
    final remote = await pick(l10n.gitMenuPickRemote, remotes);
    if (remote == null) return null;
    final refs = await git.service.refs();
    final branches = <String>{
      for (final ref in refs)
        if (ref.kind == IdeGitRefKind.remote &&
            (ref.remote == remote || ref.name.startsWith('$remote/')))
          ref.name.startsWith('$remote/')
              ? ref.name.substring(remote.length + 1)
              : ref.name,
    }.toList()..sort();
    final branch = await pick(l10n.gitMenuPickBranch, branches);
    return branch == null ? null : (remote, branch);
  }

  // The branch actions already have a host in ScmService; their public
  // methods cover Update Project, Manage Remotes and the branch popup.
  final branchHost = _ActionsHost(scm);
  final branchActions = IdeGitBranchActions(context, git, branchHost);

  return GitMenuActions(
    pull: () => run(git.pull),
    pullRebase: () => run(git.pullRebase),
    pullFrom: () => run(() async {
      final picked = await pickRemoteAndBranch();
      if (picked != null) {
        await git.pullFrom(picked.$1, picked.$2);
      }
    }),
    push: () => run(git.push),
    pushForce: () => run(git.pushForce),
    pushTo: () => run(() async {
      final picked = await pickRemoteAndBranch();
      if (picked != null) {
        await git.pushTo(picked.$1, picked.$2);
      }
    }),
    pushToForce: () => run(() async {
      final picked = await pickRemoteAndBranch();
      if (picked != null) {
        await git.pushToForce(picked.$1, picked.$2);
      }
    }),
    fetch: () => run(() => git.fetch()),
    fetchPrune: () => run(() => git.fetch(prune: true)),
    fetchDelete: () => run(() => git.fetch(prune: true, pruneTags: true)),
    fetchAll: () => run(() async {
      await Future.wait([
        for (final (_, repository) in scm.workspace.repositories)
          repository.fetch(),
      ]);
    }),
    clone: clone,
    checkout: () => scm.checkout(),
    commit: () => scm.onScmView((view) => unawaited(view.commit())),
    commitAndPush: () =>
        scm.onScmView((view) => unawaited(view.commitAndPush())),
    updateProject: () => unawaited(branchActions.updateProject()),
    branch: () => scm.showBranchPopup(),
    remote: () => unawaited(branchActions.manageRemotes()),
    stash: () => unawaited(
      ideGitStashChanges(context, git).catchError((Object error) {
        host.report(error);
        return false;
      }),
    ),
    tag: () => ideGitNewTag(context, git, run),
    worktree: () => ideGitNewWorktree(context, git, run),
    showOutput: () => unawaited(ideGitShowOutput(context, git)),
  );
}

/// Shows `git status` in a dialog: the Git menu's Show Git Output.
Future<void> ideGitShowOutput(
  BuildContext context,
  IdeGitRepository git,
) async {
  final output = await git.service.run(['status']);
  final text = '${output.stdout}${output.stderr}';
  await showIdeDialog(
    context,
    message: context.l10n.gitMenuShowOutput,
    detail: text.isEmpty ? '(no output)' : text,
    buttons: [context.l10n.commonOk],
    type: IdeDialogType.info,
  );
}

/// Asks for a name and message, then tags HEAD with them: the Git menu's
/// Tags.
Future<void> ideGitNewTag(
  BuildContext context,
  IdeGitRepository git,
  void Function(Future<void> Function()) run,
) async {
  final l10n = context.l10n;
  final result = await showIdeInputDialog(
    context,
    message: l10n.gitLogNewTag,
    buttons: [l10n.gitLogCreateTag],
    inputs: [
      IdeDialogInput(placeholder: l10n.gitTagName),
      IdeDialogInput(placeholder: l10n.gitTagMessage),
    ],
    type: IdeDialogType.question,
  );
  if (result == null) return;
  final name = result.values.first.trim();
  if (name.isEmpty) return;
  final head = await git.headCommit();
  if (head == null) return;
  final message = result.values[1].trim();
  run(() => git.tag(name, head.id, message: message.isEmpty ? null : message));
}

/// Asks for a folder name and makes a worktree beside the repository, on a
/// new branch of that name: the Git menu's Worktree.
Future<void> ideGitNewWorktree(
  BuildContext context,
  IdeGitRepository git,
  void Function(Future<void> Function()) run,
) async {
  final result = await showIdeInputDialog(
    context,
    message: context.l10n.gitMenuWorktree,
    buttons: [context.l10n.gitMenuNewWorktree],
    inputs: [IdeDialogInput(placeholder: context.l10n.gitTagName)],
    type: IdeDialogType.question,
  );
  if (result == null) return;
  final name = result.values.first.trim();
  if (name.isEmpty) return;
  run(() async {
    final paths = git.service.pathContext;
    final path = paths.join(paths.dirname(git.service.root), name);
    await git.addWorktree(path, newBranch: name);
  });
}

/// The branch actions' host, with the SCM service's own implementations.
class _ActionsHost implements IdeGitBranchHost {
  _ActionsHost(this.scm);

  final ScmService scm;

  @override
  IdeNotifications get notifications => scm.workspace.notifications;

  @override
  IdeFileService get files => scm.workspace.files;

  @override
  IdeGitFavoriteBranches get favoriteBranches => scm.favoriteBranches;

  @override
  IdeScmSession get session => scm.session;

  @override
  List<IdeGitRepository> get repositories => [
    for (final (_, git) in scm.workspace.repositories) git,
  ];

  @override
  Future<void> run(Future<void> Function() operation) async {
    try {
      await operation();
    } catch (error) {
      scm.host.report(error);
    }
  }

  @override
  void showDiff(List<IdeGitDiffFile> files) {
    scm.host.showView(IdeSideView.sourceControl);
    scm.session.log.showDiff(files, 0, focus: false);
  }

  @override
  void showOnly(IdeGitRepository git, String graphBranch) {
    scm.host.showView(IdeSideView.sourceControl);
    git.graphBranch = graphBranch;
  }
}
