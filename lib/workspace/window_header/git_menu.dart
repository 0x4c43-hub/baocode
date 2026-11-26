// The Git menu: the commands grouped as Pull/Push, Commit, Changes,
// Branches, Remotes, Stash, Tags and Worktree. Each entry is a label and an
// action, supplied by the window or by the view that shows it. What is
// unavailable in the current window (no repository, no folder) is left out
// rather than shown disabled, as the app's other menus do.

import 'package:flutter/widgets.dart';

import '../../l10n/l10n.dart';
import '../../l10n/custom_strings.dart';
import 'header_menu.dart';

/// What the Git menu can do, supplied by the workbench or the Source
/// Control view. Every callback is optional: an absent one leaves its item
/// out of the menu.
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
List<HeaderMenuItem> gitMenuItems(
  AppLocalizations l10n,
  CustomStrings custom,
  GitMenuActions a,
) {
  HeaderMenuItem item(String label, VoidCallback? run) =>
      HeaderMenuItem(label, onSelected: run ?? () {});
  HeaderMenuItem submenu(String label, List<HeaderMenuItem> entries) =>
      HeaderMenuItem(label, onSelected: () {}, submenu: entries);

  final pullPush = <HeaderMenuItem>[
    if (a.updateProject != null) item(custom.gitMenuSync, a.updateProject),
    if (a.pull != null ||
        a.pullRebase != null ||
        a.pullFrom != null ||
        a.push != null ||
        a.pushForce != null ||
        a.pushTo != null ||
        a.pushToForce != null ||
        a.fetch != null ||
        a.fetchPrune != null ||
        a.fetchDelete != null ||
        a.fetchAll != null)
      const HeaderMenuItem.rule(),
    if (a.pull != null) item(l10n.scmPull, a.pull),
    if (a.pullRebase != null) item(custom.gitMenuPullRebase, a.pullRebase),
    if (a.pullFrom != null) item(custom.gitMenuPullFrom, a.pullFrom),
    if (a.pull != null || a.pullRebase != null || a.pullFrom != null)
      const HeaderMenuItem.rule(),
    if (a.push != null) item(l10n.scmPush, a.push),
    if (a.pushForce != null) item(custom.gitMenuPushForce, a.pushForce),
    if (a.pushTo != null) item(custom.gitMenuPushTo, a.pushTo),
    if (a.pushToForce != null) item(custom.gitMenuPushToForce, a.pushToForce),
    if (a.push != null ||
        a.pushForce != null ||
        a.pushTo != null ||
        a.pushToForce != null)
      const HeaderMenuItem.rule(),
    if (a.fetch != null) item(l10n.scmFetch, a.fetch),
    if (a.fetchPrune != null) item(custom.gitMenuFetchPrune, a.fetchPrune),
    if (a.fetchDelete != null) item(custom.gitMenuFetchDelete, a.fetchDelete),
    if (a.fetchAll != null) item(custom.gitMenuFetchAll, a.fetchAll),
  ];

  return [
    if (a.pull != null) item(l10n.scmPull, a.pull),
    if (a.push != null) item(l10n.scmPush, a.push),
    if (a.clone != null) item(custom.gitMenuClone, a.clone),
    if (a.checkout != null) item(custom.gitMenuCheckout, a.checkout),
    if (a.fetch != null) item(l10n.scmFetch, a.fetch),
    if (a.clone != null || a.checkout != null || a.fetch != null)
      const HeaderMenuItem.rule(),
    if (a.commit != null || a.commitAndPush != null)
      submenu(custom.gitMenuCommit, [
        if (a.commit != null) item(custom.gitMenuCommitChanges, a.commit),
        if (a.commitAndPush != null)
          item(l10n.gitCommitAndPush, a.commitAndPush),
      ]),
    if (a.updateProject != null || a.stash != null)
      submenu(custom.gitMenuChanges, [
        if (a.updateProject != null)
          item(custom.gitMenuUpdateProject, a.updateProject),
        if (a.stash != null) item(custom.gitMenuStash, a.stash),
      ]),
    if (pullPush.isNotEmpty) submenu(custom.gitMenuPullPush, pullPush),
    if (a.branch != null)
      submenu(custom.gitMenuBranches, [item(custom.gitMenuBranches, a.branch)]),
    if (a.remote != null)
      submenu(custom.gitMenuRemotes, [item(custom.gitMenuRemotes, a.remote)]),
    if (a.stash != null)
      submenu(custom.gitMenuStash, [item(custom.gitMenuStash, a.stash)]),
    if (a.tag != null)
      submenu(custom.gitMenuTags, [item(custom.gitMenuTags, a.tag)]),
    if (a.worktree != null)
      submenu(custom.gitMenuWorktree, [
        item(custom.gitMenuWorktree, a.worktree),
      ]),
    const HeaderMenuItem.rule(),
    if (a.showOutput != null) item(custom.gitMenuShowOutput, a.showOutput),
  ];
}
