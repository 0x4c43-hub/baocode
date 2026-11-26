import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';
import '../../theme/app_theme.dart';
import '../../theme/codicons.dart';
import '../../theme/workbench_theme.dart' show themeColors;
import '../ide_dates.dart';
import '../ide_hover.dart';
import 'git_model.dart' show IdeGitBlameInformation;

/// A commit's details, as GitLens's card shows them on a line's blame: who
/// made it and when, its message, its id (to copy), and its author's
/// address and date.
class IdeGitBlameCard extends StatelessWidget {
  const IdeGitBlameCard({
    super.key,
    required this.commit,
    required this.width,
    this.onCopy,
    this.onOpenCommit,
  });

  final IdeGitBlameInformation commit;
  final double width;
  final VoidCallback? onCopy;

  /// Shows the commit's changes. Pressed, its hash shows them.
  final VoidCallback? onOpenCommit;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final date = commit.authorDate;
    final author = commit.authorName ?? '';
    final email = commit.authorEmail;
    final subject = commit.subject;
    final short = commit.hash.length > 8
        ? commit.hash.substring(0, 8)
        : commit.hash;
    final muted = TextStyle(
      color: AppColors.textMuted,
      fontSize: 11,
      height: 1.45,
    );
    return IdeHoverBox(
      compact: false,
      maxWidth: width,
      padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 18,
                height: 18,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: themeColors['badge.background'],
                ),
                child: Text(
                  author.isEmpty ? '?' : author.substring(0, 1).toUpperCase(),
                  style: TextStyle(
                    fontSize: 10,
                    height: 1.2,
                    color: themeColors['badge.foreground'],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  author,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (date != null) ...[
                const SizedBox(width: 8),
                Text(
                  ideFromNow(date, ago: true, fullWords: true, l10n: l10n),
                  style: muted,
                ),
              ],
            ],
          ),
          if (subject != null && subject.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                subject,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13, height: 1.45),
              ),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 9),
            child: Divider(
              height: 1,
              thickness: 1,
              color: themeColors['editorWidget.border'],
            ),
          ),
          Row(
            children: [
              if (onOpenCommit case final open?)
                MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: open,
                    child: _hash(context, short),
                  ),
                )
              else
                _hash(context, short),
              if (onCopy case final copy?)
                Tooltip(
                  message: MaterialLocalizations.of(context).copyButtonLabel,
                  child: MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: copy,
                      child: Padding(
                        padding: const EdgeInsets.all(6),
                        child: Icon(
                          Codicons.copy,
                          size: 12,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ),
                  ),
                ),
              const Spacer(),
              if (email != null && email.isNotEmpty)
                Flexible(
                  child: Text(
                    '<$email>',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.right,
                    style: muted,
                  ),
                ),
            ],
          ),
          if (date != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                '${date.year}/${_two(date.month)}/${_two(date.day)} '
                '${_two(date.hour)}:${_two(date.minute)}',
                style: muted,
              ),
            ),
        ],
      ),
    );
  }

  /// [short] as GitLens shows a commit's id, to press for its changes.
  Widget _hash(BuildContext context, String short) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      color: themeColors['badge.background'],
      borderRadius: BorderRadius.circular(3),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Codicons.gitCommit, size: 12, color: AppColors.textMuted),
        const SizedBox(width: 5),
        Text(
          short,
          style: AppFonts.codeStyle(11).copyWith(
            color: themeColors['editor.foreground'],
          ),
        ),
      ],
    ),
  );

  static String _two(int value) => '$value'.padLeft(2, '0');
}
