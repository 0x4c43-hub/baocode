// The Git menu: its groups and the two-level Pull, Push submenu.

import 'package:baocode/l10n/app_localizations_en.dart';
import 'package:baocode/l10n/custom_strings.dart';
import 'package:baocode/workspace/window_header/git_menu.dart';
import 'package:baocode/workspace/window_header/header_menu.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final l10n = AppLocalizationsEn();
  const custom = CustomStrings('en');

  test('the Git menu groups the commands with rules between them', () {
    final opened = <String>[];
    final items = gitMenuItems(
      l10n,
      custom,
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
      custom.gitMenuClone,
      custom.gitMenuCheckout,
      l10n.scmFetch,
      custom.gitMenuCommit,
      custom.gitMenuChanges,
      custom.gitMenuPullPush,
      custom.gitMenuBranches,
      custom.gitMenuRemotes,
      custom.gitMenuStash,
      custom.gitMenuTags,
      custom.gitMenuWorktree,
      custom.gitMenuShowOutput,
    ]);
    // The first rule falls between Fetch and the grouping menus.
    expect(items[5], isA<HeaderMenuItem>().having((i) => i.rule, 'rule', true));
  });

  test('the Pull, Push submenu has Sync, variants and Fetch', () {
    final opened = <String>[];
    final items = gitMenuItems(
      l10n,
      custom,
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
      (item) => !item.rule && item.label == custom.gitMenuPullPush,
    );
    final submenu = pullPush.submenu!;
    final labels = [
      for (final item in submenu)
        if (!item.rule) item.label,
    ];
    expect(labels, [
      custom.gitMenuSync,
      l10n.scmPull,
      custom.gitMenuPullRebase,
      custom.gitMenuPullFrom,
      l10n.scmPush,
      custom.gitMenuPushForce,
      custom.gitMenuPushTo,
      custom.gitMenuPushToForce,
      l10n.scmFetch,
      custom.gitMenuFetchPrune,
      custom.gitMenuFetchDelete,
      custom.gitMenuFetchAll,
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
    final items = gitMenuItems(l10n, custom, const GitMenuActions());
    expect(items, [const HeaderMenuItem.rule()]);
  });
}
