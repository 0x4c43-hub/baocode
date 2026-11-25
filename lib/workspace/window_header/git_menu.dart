// The Git menu of the header's menu bar: the commands grouped as
// Pull/Push, Commit, Changes, Branches, Remotes, Stash, Tags and Worktree.
// Each entry is a label and an action, supplied by the workbench. What is
// unavailable in the current window (no repository, no folder) is left out
// rather than shown disabled, as the app's other menus do.

import '../../l10n/l10n.dart';
import 'header_menu.dart';

/// What the Git menu can do, supplied by the workbench. Every callback is
/// optional: an absent one leaves its item out of the menu.
class GitMenuActions {
  const GitMenuActions({
    this.pull,
    this.pullRebase,
    this.pullFrom,
    this.push,
    this.pushForce,
    this.pushTo,
    this.pushToForce,
    this.fetch,
    this.fetchPrune,
    this.fetchDelete,
    this.fetchAll,
    this.clone,
    this.checkout,
    this.commit,
    this.commitAndPush,
    this.updateProject,
    this.branch,
    this.remote,
    this.stash,
    this.tag,
    this.worktree,
    this.showOutput,
  });

  final VoidCallback? pull;
  final VoidCallback? pullRebase;
  final VoidCallback? pullFrom;
  final VoidCallback? push;
  final VoidCallback? pushForce;
  final VoidCallback? pushTo;
  final VoidCallback? pushToForce;
  final VoidCallback? fetch;
  final VoidCallback? fetchPrune;
  final VoidCallback? fetchDelete;
  final VoidCallback? fetchAll;
  final VoidCallback? clone;
  final VoidCallback? checkout;
  final VoidCallback? commit;
  final VoidCallback? commitAndPush;
  final VoidCallback? updateProject;
  final VoidCallback? branch;
  final VoidCallback? remote;
  final VoidCallback? stash;
  final VoidCallback? tag;
  final VoidCallback? worktree;
  final VoidCallback? showOutput;
}

/// The Git menu's entries, grouped with rules between them.
List<HeaderMenuItem> gitMenuItems(AppLocalizations l10n, GitMenuActions a) {
  HeaderMenuItem item(String label, VoidCallback? run) =>
      HeaderMenuItem(label, onSelected: run ?? () {});
  HeaderMenuItem submenu(String label, List<HeaderMenuItem> entries) =>
      HeaderMenuItem(label, onSelected: () {}, submenu: entries);

  final pullPush = <HeaderMenuItem>[
    if (a.updateProject != null) item(l10n.gitMenuSync, a.updateProject),
    if (a.pull != null ||
        a.pullRebase != null ||
        a.pullFrom != null ||
        a.push != null ||
        a.pushForce != null ||
        a.pushTo != null ||
        a.pushToForce != null ||
        a.fetch != null ||
        a.fetchDelete != null ||
        a.fetchAll != null)
      const HeaderMenuItem.rule(),
    if (a.pull != null) item(l10n.scmPull, a.pull),
    if (a.pullRebase != null) item(l10n.gitMenuPullRebase, a.pullRebase),
    if (a.pullFrom != null) item(l10n.gitMenuPullFrom, a.pullFrom),
    const HeaderMenuItem.rule(),
    if (a.push != null) item(l10n.scmPush, a.push),
    if (a.pushForce != null) item(l10n.gitMenuPushForce, a.pushForce),
    if (a.pushTo != null) item(l10n.gitMenuPushTo, a.pushTo),
    if (a.pushToForce != null) item(l10n.gitMenuPushToForce, a.pushToForce),
    const HeaderMenuItem.rule(),
    if (a.fetch != null) item(l10n.scmFetch, a.fetch),
    if (a.fetchPrune != null) item(l10n.gitMenuFetchPrune, a.fetchPrune),
    if (a.fetchDelete != null) item(l10n.gitMenuFetchDelete, a.fetchDelete),
    if (a.fetchAll != null) item(l10n.gitMenuFetchAll, a.fetchAll),
  ];

  return [
    if (a.pull != null) item(l10n.scmPull, a.pull),
    if (a.push != null) item(l10n.scmPush, a.push),
    if (a.clone != null) item(l10n.gitMenuClone, a.clone),
    if (a.checkout != null) item(l10n.gitMenuCheckout, a.checkout),
    if (a.fetch != null) item(l10n.scmFetch, a.fetch),
    const HeaderMenuItem.rule(),
    if (a.commit != null || a.commitAndPush != null)
      submenu(l10n.gitMenuCommit, [
        if (a.commit != null) item(l10n.gitMenuCommitChanges, a.commit),
        if (a.commitAndPush != null)
          item(l10n.gitCommitAndPush, a.commitAndPush),
      ]),
    if (a.updateProject != null || a.stash != null)
      submenu(l10n.gitMenuChanges, [
        if (a.updateProject != null)
          item(l10n.gitMenuUpdateProject, a.updateProject),
        if (a.stash != null) item(l10n.gitMenuStash, a.stash),
      ]),
    if (pullPush.isNotEmpty) submenu(l10n.gitMenuPullPush, pullPush),
    if (a.branch != null)
      submenu(l10n.gitMenuBranches, [item(l10n.gitMenuBranches, a.branch)]),
    if (a.remote != null)
      submenu(l10n.gitMenuRemotes, [item(l10n.gitMenuRemotes, a.remote)]),
    if (a.stash != null)
      submenu(l10n.gitMenuStash, [item(l10n.gitMenuStash, a.stash)]),
    if (a.tag != null)
      submenu(l10n.gitMenuTags, [item(l10n.gitMenuTags, a.tag)]),
    if (a.worktree != null)
      submenu(l10n.gitMenuWorktree, [item(l10n.gitMenuWorktree, a.worktree)]),
    const HeaderMenuItem.rule(),
    if (a.showOutput != null) item(l10n.gitMenuShowOutput, a.showOutput),
  ];
}
