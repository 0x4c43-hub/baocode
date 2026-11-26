# BaoCode 2：定制分支的改动与合并

这个分支只比上游多这几件事：窗口内的 Git 菜单、终端 ZMODEM（`rz`/`sz`）、
从源码自动更新、终端点击即聚焦与 Ctrl/⌘ + 滚轮缩放、终端里 Ctrl+W 等
控制字符交给 shell；外加自己的 edition、bundle id 和本机签名。其余代码与上游一致。

合并上游（`tool/sync_custom.sh`，或手工 `git merge`）时的冲突只可能出现在
下面这些“插入点”，新增文件本身从不冲突。

## 只属于我们（新增文件）

| 文件 | 做什么 |
| --- | --- |
| `lib/ide/terminal/terminal_zmodem.dart` | ZMODEM 协议：`rz`/`sz` 的收发、流控、重传 |
| `lib/ide/terminal/terminal_zmodem_banner.dart` | 传输进度条（`ZmodemOverlay`），两种终端视图共用 |
| `lib/ide/terminal/terminal_focus.dart` | 键盘在终端里时，窗口快捷键让开（Ctrl+W、Ctrl+A 等交给 shell） |
| `lib/ide/terminal/terminal_zoom.dart` | Ctrl/⌘ + 滚轮缩放终端字号，写回 `terminal.integrated.fontSize` |
| `lib/workspace/window_header/git_menu.dart` | Git 菜单的条目与分组 |
| `lib/ide/git/ide_git_log_view.dart` 里的 Git 页 | 提交历史、分支、远端等界面 |
| `lib/update/source_update_controller.dart` | 源码更新：查上游版本、合并、构建、安装 |
| `lib/l10n/custom_strings.dart` | 本分支的全部文案（见下） |
| `lib/platform/app_edition.dart` | 定制 edition 与 bundle id |
| `tool/sync_custom.sh`、`tool/in_app_update.sh` | 合并上游、构建、替换并重启 |

## 上游文件里的插入点

| 文件 | 我们加了什么 |
| --- | --- |
| `lib/main.dart` | 定制版不走官方更新，改为启动源码更新控制器；`TerminalZoom.follow(settings)` |
| `lib/workbench.dart` | 检查更新的命令、构建完成的通知、侧栏“更新”胶囊的接线 |
| `lib/sidebar/sidebar.dart` | 齿轮旁的“更新”胶囊（源码更新用） |
| `lib/settings/app_settings.dart` | 把源码更新控制器传给设置页 |
| `lib/settings/pages/updates_page.dart` | “源码更新”卡片与进度条 |
| `lib/ide/terminal/terminal_instance.dart` | 终端输出里识别 ZMODEM 会话并接管 |
| `lib/ide/terminal/terminal_panel.dart`、`lib/workspace/terminal_deck.dart` | 终端上叠 `ZmodemOverlay` |
| `lib/ide/terminal/terminal_view.dart` | 点击即取回键盘与输入法连接；Ctrl/⌘ + 滚轮缩放；失效连接的兜底 |
| `lib/ide/terminal/terminal_widget.dart` | 滚轮带 Ctrl/⌘ 时交给缩放，不滚动 |
| `packages/bao_remote/lib/src/claude/claude_sessions.dart` | 会话分支的末梢取最后一条**消息**，`system/api_error` 之类的记录不再把分支截断 |
| `lib/kernel/claude_code/claude_code_kernel.dart` | 打开会话先读 25 轮（上游 10），往上每次 50 轮（上游 20） |
| `lib/chat/chat_history_view.dart` | 离顶部 900px 就预取更早的分页（上游 300） |
| `lib/workspace/window_header/header_menu.dart`、`header_menu_bar.dart`、`window_header.dart` | 顶栏的 Git 菜单与快捷键 |
| `lib/platform/context_menu_io.dart`、`shell_command_io.dart` | 定制 edition 的名字与路径 |
| `macos/Runner/Info.plist`、`AppInfo.xcconfig`、`project.pbxproj` | bundle id、应用名 |
| `tool/build_macos.dart` | 本机签名身份时不加 hardened runtime |
| `packages/bao_pty/lib/src/pty_io.dart` | 写被拒时的重试策略（ZMODEM 吞吐） |

## 文案规则

**所有本分支的文案只写在 `lib/l10n/custom_strings.dart`**，读作
`context.custom.xxx`。不要加到 `lib/l10n/app_en.arb` / `app_zh.arb`：
上游每版都在改这两个文件和它们的生成物，我们的键夹在中间，每次合并都会冲突。
`app_localizations*.dart` 是 `flutter gen-l10n` 的产物，不要手改。

## 合并上游之后

```bash
flutter gen-l10n                     # 或 flutter pub get，会顺带生成
dart analyze lib test                # 不应有 error/warning
flutter test test/workspace/git_menu_test.dart \
  test/update/{updates_page,sidebar_update_button,source_update}_test.dart \
  test/ide/terminal/terminal_zmodem_test.dart
dart format lib test tool
```

冲突高发区按顺序：`lib/l10n/*`（应已无我们的改动）、
`lib/workspace/window_header/header_menu_bar.dart`、`lib/ide/terminal/terminal_instance.dart`、
`lib/workbench.dart`。合并后先用 `dart analyze` 找漏掉的插入点，再跑上面的测试。
