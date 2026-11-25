// The Git menu: its groups and the two-level Pull, Push submenu.

import 'package:baocode/l10n/app_localizations_en.dart';
import 'package:baocode/workspace/window_header/git_menu.dart';
import 'package:baocode/workspace/window_header/header_menu.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final l10n = AppLocalizationsEn();

  test('the Git menu groups the commands with rules between them', () {
    final opened = <String>[];
    final items = gitMenuItems(
      l10n,
      GitMenuActions(
        pull: () => opened.add('pull'),
        push: () => opened.add('push'),
        clone: () => opened.add('clone'),
        checkout: () => opened.add('checkout'),
        fetch: () => opened.add('fetch'),
        commit: () => opened.add('commit'),
        commitAndPush: () => opened.add('commitAndPush'),
        updateProject: () => opened.add('update'),
        branch: () => opened.add('branch'),
        remote: () => opened.add('remote'),
        stash: () => opened.add('stash'),
        tag: () => opened.add('tag'),
        worktree: () => opened.add('worktree'),
        showOutput: () => opened.add('output'),
      ),
    );
    final labels = [
      for (final item in items)
        if (!item.rule) item.label,
    ];
    expect(labels, [
      l10n.scmPull,
      l10n.scmPush,
      l10n.gitMenuClone,
      l10n.gitMenuCheckout,
      l10n.scmFetch,
      l10n.gitMenuCommit,
      l10n.gitMenuChanges,
      l10n.gitMenuPullPush,
      l10n.gitMenuBranches,
      l10n.gitMenuRemotes,
      l10n.gitMenuStash,
      l10n.gitMenuTags,
      l10n.gitMenuWorktree,
      l10n.gitMenuShowOutput,
    ]);
    // The first rule falls between Fetch and the grouping menus.
    expect(items[5], isA<HeaderMenuItem>().having((i) => i.rule, 'rule', true));
  });

  test('the Pull, Push submenu has Sync, variants and Fetch', () {
    final opened = <String>[];
    final items = gitMenuItems(
      l10n,
      GitMenuActions(
        updateProject: () => opened.add('sync'),
        pull: () => opened.add('pull'),
        pullRebase: () => opened.add('pullRebase'),
        pullFrom: () => opened.add('pullFrom'),
        push: () => opened.add('push'),
        pushForce: () => opened.add('pushForce'),
        pushTo: () => opened.add('pushTo'),
        pushToForce: () => opened.add('pushToForce'),
        fetch: () => opened.add('fetch'),
        fetchPrune: () => opened.add('fetchPrune'),
        fetchDelete: () => opened.add('fetchDelete'),
        fetchAll: () => opened.add('fetchAll'),
      ),
    );
    final pullPush = items.firstWhere(
      (item) => !item.rule && item.label == l10n.gitMenuPullPush,
    );
    final submenu = pullPush.submenu!;
    final labels = [
      for (final item in submenu)
        if (!item.rule) item.label,
    ];
    expect(labels, [
      l10n.gitMenuSync,
      l10n.scmPull,
      l10n.gitMenuPullRebase,
      l10n.gitMenuPullFrom,
      l10n.scmPush,
      l10n.gitMenuPushForce,
      l10n.gitMenuPushTo,
      l10n.gitMenuPushToForce,
      l10n.scmFetch,
      l10n.gitMenuFetchPrune,
      l10n.gitMenuFetchDelete,
      l10n.gitMenuFetchAll,
    ]);
    // Rules divide Sync, Pull, Push and Fetch; each action is callable.
    final actions = [
      for (final item in submenu)
        if (!item.rule) item.onSelected,
    ];
    for (final action in actions) {
      action!();
    }
    expect(opened, [
      'sync',
      'pull',
      'pullRebase',
      'pullFrom',
      'push',
      'pushForce',
      'pushTo',
      'pushToForce',
      'fetch',
      'fetchPrune',
      'fetchDelete',
      'fetchAll',
    ]);
  });

  test('what is unavailable is left out of the menu', () {
    final items = gitMenuItems(l10n, const GitMenuActions());
    expect(items, [const HeaderMenuItem.rule()]);
  });
}
