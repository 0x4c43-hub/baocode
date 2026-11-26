/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

import 'dart:async';

import 'package:flutter/material.dart';

import '../../l10n/custom_strings.dart';
import '../../theme/codicons.dart';
import 'terminal_instance.dart';
import 'terminal_zmodem.dart';

/// The ZMODEM transfer of a terminal, over it: how far along it is, how
/// fast, and Cancel. Shown by every view that puts a [TerminalInstance]'s
/// screen on a widget, so the meter reads the same wherever it is.
class ZmodemOverlay extends StatelessWidget {
  const ZmodemOverlay({super.key, required this.shell, required this.child});

  final TerminalInstance shell;
  final Widget child;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: shell,
    builder: (context, child) {
      final transfer = shell.zmodem;
      return Stack(
        children: [
          Positioned.fill(child: child!),
          if (transfer != null && transfer.active)
            Positioned(
              left: 16,
              right: 16,
              bottom: 12,
              child: ZmodemBanner(
                session: transfer,
                onCancel: shell.cancelZmodem,
              ),
            ),
        ],
      );
    },
    child: child,
  );
}

class ZmodemBanner extends StatefulWidget {
  const ZmodemBanner({
    super.key,
    required this.session,
    required this.onCancel,
  });

  final ZmodemSession session;
  final VoidCallback onCancel;

  @override
  State<ZmodemBanner> createState() => _ZmodemBannerState();
}

class _ZmodemBannerState extends State<ZmodemBanner> {
  /// Samples the session for how fast it is going: what it moved since the
  /// last look, smoothed, as a meter of this second's rate.
  Timer? _tick;
  int _bytes = 0;
  DateTime _at = DateTime.now();
  double _speed = 0;

  ZmodemSession get session => widget.session;

  @override
  void initState() {
    super.initState();
    _bytes = session.transferred;
    _tick = Timer.periodic(const Duration(milliseconds: 500), (_) => _sample());
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  void _sample() {
    final now = DateTime.now();
    final bytes = session.transferred;
    final seconds = now.difference(_at).inMilliseconds / 1000;
    if (seconds > 0 && bytes >= _bytes) {
      final current = (bytes - _bytes) / seconds;
      _speed = _speed == 0 ? current : _speed * 0.6 + current * 0.4;
    }
    _bytes = bytes;
    _at = now;
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final custom = context.custom;
    final theme = Theme.of(context);
    final waiting = session.waitingForUser;
    final receiving = session.direction != ZmodemDirection.upload;
    final title = waiting
        ? (receiving ? custom.zmodemChooseSave : custom.zmodemChooseFiles)
        : (receiving ? custom.zmodemReceiving : custom.zmodemSending);
    final total = session.total;
    final progress = total > 0
        ? (session.transferred / total).clamp(0.0, 1.0)
        : null;
    final files = session.fileCount > 1
        ? '  ${session.fileIndex}/${session.fileCount}'
        : '';
    final percent = progress == null ? null : '${(progress * 100).floor()}%';
    final speed = !waiting && _speed > 0
        ? '  ${zmodemBytes(_speed.round())}/s'
        : '';
    final detail = waiting
        ? (session.name ?? '')
        : '${session.name ?? ''}${session.name == null ? '' : '  '}'
              '${percent == null ? '' : '$percent  '}'
              '${zmodemBytes(session.transferred)}'
              '${total > 0 ? ' / ${zmodemBytes(total)}' : ''}$files$speed';
    return Material(
      color: theme.colorScheme.surface,
      elevation: 6,
      borderRadius: BorderRadius.circular(8),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 9, 4, 9),
        child: Row(
          children: [
            Icon(
              receiving ? Codicons.cloudDownload : Codicons.cloudUpload,
              size: 16,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (detail.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      detail,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                  if (!waiting) ...[
                    const SizedBox(height: 6),
                    LinearProgressIndicator(
                      value: progress,
                      minHeight: 3,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 6),
            IconButton(
              icon: const Icon(Codicons.close, size: 14),
              tooltip: custom.zmodemCancel,
              visualDensity: VisualDensity.compact,
              onPressed: widget.onCancel,
            ),
          ],
        ),
      ),
    );
  }
}

String zmodemBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
}
