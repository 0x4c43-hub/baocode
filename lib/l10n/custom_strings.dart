// This branch's own strings, apart from the upstream's .arb files: those
// change with every upstream release, and a key of ours among them makes
// every merge of upstream a conflict. Widgets read them as
// `context.custom`.
import 'package:flutter/widgets.dart';

/// The strings this branch adds: the Git menu, ZMODEM transfers, and the
/// update that builds upstream's version from this checkout.
class CustomStrings {
  const CustomStrings(this.languageCode);

  /// The locale's, as `Localizations.localeOf` gives it: `zh` for Chinese,
  /// anything else English.
  final String languageCode;

  bool get _zh => languageCode.startsWith('zh');

  String get menuGit => 'Git';

  String get sidePanelFindFile => _zh ? '按文件名搜索文件' : 'Search files by name';

  String get sourceUpdateTitle => _zh ? '源码更新' : 'Source updates';

  String get sourceUpdatePageDescription => _zh
      ? 'BaoCode 2 从源码更新：上游发布新版本后，在这里构建并安装。'
      : 'BaoCode 2 updates from its sources: a version upstream publishes '
            'is built here, then installed.';

  String sourceUpdateUpToDate(String version) => _zh
      ? '$version 已是最新：上游没有发布更新的版本。'
      : '$version is the newest: upstream publishes nothing newer.';

  String sourceUpdateAvailable(String version) => _zh
      ? '上游已发布 $version，可以在后台构建。'
      : 'Upstream publishes $version; it can be built in the background.';

  String get sourceUpdateBuilding => _zh
      ? '正在合并、测试并构建；完成后退出 BaoCode 2 即会安装。'
      : 'Merging, testing and building; BaoCode 2 installs it once it quits.';

  String get sourceUpdateReady => _zh
      ? '新版本已构建好，退出 BaoCode 2 后自动安装并重新打开。'
      : 'The new version is built. It installs when BaoCode 2 quits, and '
            'opens again.';

  String sourceUpdateFailed(String error) =>
      _zh ? '更新没有完成：$error' : 'The update did not finish: $error';

  String get sourceUpdateUpdateNow => _zh ? '立即更新' : 'Update Now';

  String get sourceUpdateLog => _zh ? '查看日志' : 'Show Log';

  String get gitMenuSync => _zh ? '同步' : 'Sync';

  String get gitMenuClone => _zh ? '克隆' : 'Clone';

  String get gitMenuCheckout => _zh ? '签出到…' : 'Checkout to…';

  String get gitMenuCommit => _zh ? '提交' : 'Commit';

  String get gitMenuCommitChanges => _zh ? '提交更改…' : 'Commit Changes…';

  String get gitMenuChanges => _zh ? '更改' : 'Changes';

  String get gitMenuUpdateProject => _zh ? '更新项目' : 'Update Project';

  String get gitMenuPullPush => _zh ? '拉取，推送' : 'Pull, Push';

  String get gitMenuPullRebase => _zh ? '拉取（变基）' : 'Pull (Rebase)';

  String get gitMenuPullFrom => _zh ? '拉取自…' : 'Pull from…';

  String get gitMenuPushForce => _zh ? '推送（强制）' : 'Push (Force)';

  String get gitMenuPushTo => _zh ? '推送到…' : 'Push to…';

  String get gitMenuPushToForce => _zh ? '推送到…（强制）' : 'Push to… (Force)';

  String get gitMenuFetchPrune => _zh ? '抓取（清理）' : 'Fetch (Prune)';

  String get gitMenuFetchDelete => _zh ? '抓取（删除）' : 'Fetch (Delete)';

  String get gitMenuFetchAll => _zh ? '从所有远程存储库中抓取' : 'Fetch from All Remotes';

  String get gitMenuBranches => _zh ? '分支' : 'Branches';

  String get gitMenuRemotes => _zh ? '远程' : 'Remotes';

  String get gitMenuStash => _zh ? '存储' : 'Stash';

  String get gitMenuTags => _zh ? '标记' : 'Tags';

  String get gitMenuWorktree => _zh ? '工作树' : 'Worktree';

  String get gitMenuShowOutput => _zh ? '显示 GIT 输出' : 'Show Git Output';

  String get gitMenuNoRemote =>
      _zh ? '没有可用的远程仓库。' : 'There is no remote to work with.';

  String get gitMenuPickRemote => _zh ? '选择远程仓库' : 'Pick a remote';

  String get gitMenuPickBranch => _zh ? '选择分支' : 'Pick a branch';

  String get gitMenuNewWorktree => _zh ? '添加工作树' : 'Add Worktree';

  String get zmodemReceiving => _zh ? '正在接收' : 'Receiving';

  String get zmodemSending => _zh ? '正在发送' : 'Sending';

  String get zmodemChooseSave => _zh ? '选择保存位置…' : 'Choose where to save…';

  String get zmodemChooseFiles => _zh ? '选择要发送的文件…' : 'Choose files to send…';

  String get zmodemCancel => _zh ? '取消传输' : 'Cancel transfer';
}

extension CustomStringsContext on BuildContext {
  /// This branch's strings, in the locale in scope; English where there is
  /// none (a dialog built above the app's Localizations).
  CustomStrings get custom =>
      CustomStrings(Localizations.maybeLocaleOf(this)?.languageCode ?? 'en');
}
