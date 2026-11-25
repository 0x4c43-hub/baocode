import 'dart:async';

import 'package:flutter/material.dart';

import '../../diagnostics/diagnostics_upload.dart';
import '../../ide/ide_button.dart';
import '../../ide/ide_menu.dart';
import '../../l10n/l10n.dart';
import '../../theme/codicons.dart';
import '../../update/source_update_controller.dart';
import '../../update/update_controller.dart';
import '../../update/update_service.dart';
import '../../update/update_settings.dart';
import '../../update/version.dart';
import '../user_settings.dart';
import 'data_dir_page.dart';
import 'diagnostics_dialog.dart';
import 'settings_dropdown.dart';
import 'settings_widgets.dart';

/// Settings → Updates: the version running, when it last looked for
/// another, what it found (Restart to Update), `update.mode`, uploading
/// the diagnostic logs, and the new version's notes (this one's, where it
/// is the newest).
class UpdatesSettingsPage extends StatefulWidget {
  const UpdatesSettingsPage({
    super.key,
    this.updates,
    this.source,
    this.settings,
    this.diagnostics,
  });

  /// None where the build does not update itself (a debug build).
  final UpdateController? updates;

  /// BaoCode 2's own updates, from the checkout it was built from; none
  /// where this is not that build.
  final SourceUpdateController? source;

  /// settings.json; none under test, where choices are not kept.
  final UserSettings? settings;

  /// What uploads the diagnostic logs; none under test, where the card is
  /// not shown.
  final DiagnosticsUploader? diagnostics;

  static String modeName(BuildContext context, UpdateMode mode) {
    final l10n = context.l10n;
    return switch (mode) {
      UpdateMode.automatic => l10n.updateModeDefault,
      UpdateMode.manual => l10n.updateModeManual,
      UpdateMode.none => l10n.updateModeNone,
    };
  }

  @override
  State<UpdatesSettingsPage> createState() => _UpdatesSettingsPageState();
}

class _UpdatesSettingsPageState extends State<UpdatesSettingsPage> {
  /// Why Restart to Update did not: a [ManualUpdateRequired], or the
  /// error.
  Object? _problem;

  UpdateService? get _service => widget.updates?.service;

  void _write(UpdateMode mode) {
    final settings = widget.settings;
    if (settings == null) return;
    unawaited(
      settings
          .update(
            UpdateMode.settingKey,
            mode == UpdateMode.defaultMode ? null : mode.value,
          )
          .catchError((Object error) {
            // A settings file that does not parse is left as it is; its
            // error is shown.
            debugPrint('${UpdateMode.settingKey} not kept: $error');
          }),
    );
  }

  Future<void> _check() async {
    setState(() => _problem = null);
    await _service?.check(manual: true);
  }

  Future<void> _restart() async {
    setState(() => _problem = null);
    final problem = await widget.updates?.restartToUpdate();
    if (mounted) setState(() => _problem = problem);
  }

  @override
  Widget build(BuildContext context) {
    final settings = widget.settings;
    return ListenableBuilder(
      listenable: Listenable.merge([?settings, ?_service, ?widget.source]),
      builder: (context, _) => _page(
        context,
        _service?.mode ?? UpdateMode.parse(settings?[UpdateMode.settingKey]),
      ),
    );
  }

  Widget _page(BuildContext context, UpdateMode mode) {
    final l10n = context.l10n;
    final service = _service;
    final busy =
        service?.status == UpdateStatus.checking ||
        service?.status == UpdateStatus.downloading;
    final modeName = UpdatesSettingsPage.modeName(context, mode);
    // The new version's, or this one's where it is the newest.
    final noted = service?.release?.manifest ?? service?.installed;
    final notes = noted?.notesFor(l10n.localeName);
    return SettingsPage(
      title: l10n.updatesSettingsTitle,
      description: widget.source == null
          ? l10n.updatesSettingsDescription
          : l10n.sourceUpdatePageDescription,
      children: [
        if (widget.source case final source?)
          _sourceCard(context, source)
        else
          SettingsCard(
            children: [
              SettingsRow(
                label: l10n.updateCurrentVersion,
                description: [
                  (service?.current ?? currentAppVersion).marketing,
                  switch (service?.lastChecked) {
                    final time? => l10n.updateLastChecked(
                      _format(context, time),
                    ),
                    null when service != null => l10n.updateNeverChecked,
                    null => l10n.updateUnsupported,
                  },
                ].join(' · '),
                trailing: IdeButton(
                  label: l10n.updateCheckNow,
                  icon: Codicons.refresh,
                  secondary: true,
                  onPressed:
                      service == null || busy || mode == UpdateMode.none
                      ? null
                      : () => unawaited(_check()),
                ),
              ),
              ?(service == null ? null : _status(context, service)),
            ],
          ),
        SettingsCard(
          children: [
            SettingsRow(
              label: l10n.updateMode,
              description: l10n.updateModeDescription,
              trailing: SettingsDropdown(
                current: modeName,
                semanticLabel: l10n.updateModeLabel(modeName),
                entries: () => [
                  for (final choice in UpdateMode.values)
                    IdeMenuAction(
                      UpdatesSettingsPage.modeName(context, choice),
                      checked: choice == mode,
                      onSelected: () => _write(choice),
                    ),
                ],
              ),
            ),
          ],
        ),
        if (widget.diagnostics case final diagnostics?)
          SettingsCard(
            children: [
              SettingsRow(
                label: l10n.diagnosticsTitle,
                description: l10n.diagnosticsDescription,
                trailing: SettingsButtons(
                  children: [
                    if (DataDirectoryPage.canReveal)
                      IdeButton(
                        label: l10n.revealInFileManager,
                        secondary: true,
                        onPressed: () => unawaited(
                          diagnostics.ensureFolder().then(
                            DataDirectoryPage.revealFolder,
                          ),
                        ),
                      ),
                    IdeButton(
                      label: l10n.diagnosticsUpload,
                      secondary: true,
                      onPressed: () => unawaited(
                        showDiagnosticsDialog(context, diagnostics),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        if (notes != null)
          SettingsGroup(
            title: l10n.updateReleaseNotesFor(noted!.version.marketing),
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 11,
                ),
                child: SelectableText(notes, style: SettingsText.description),
              ),
            ],
          ),
      ],
    );
  }

  /// [time] as the app's language writes a date and time.
  static String _format(BuildContext context, DateTime time) {
    final material = MaterialLocalizations.of(context);
    return '${material.formatMediumDate(time)} '
        '${material.formatTimeOfDay(TimeOfDay.fromDateTime(time))}';
  }

  /// BaoCode 2's own: the version running from this checkout, the version
  /// upstream publishes, and the build that would take it.
  Widget _sourceCard(BuildContext context, SourceUpdateController source) {
    final l10n = context.l10n;
    final busy =
        source.status == SourceUpdateStatus.checking ||
        source.status == SourceUpdateStatus.building;
    final status = switch (source.status) {
      SourceUpdateStatus.idle => null,
      SourceUpdateStatus.checking => l10n.updateChecking,
      SourceUpdateStatus.upToDate => l10n.sourceUpdateUpToDate(
        source.localVersion.marketing,
      ),
      SourceUpdateStatus.available => l10n.sourceUpdateAvailable(
        source.upstreamLabel,
      ),
      SourceUpdateStatus.building => l10n.sourceUpdateBuilding,
      SourceUpdateStatus.ready => l10n.sourceUpdateReady,
      SourceUpdateStatus.failed => l10n.sourceUpdateFailed(source.error ?? ''),
    };
    final detail = switch (source.status) {
      SourceUpdateStatus.building ||
      SourceUpdateStatus.ready ||
      SourceUpdateStatus.failed => source.logTail,
      _ => null,
    };
    return SettingsCard(
      children: [
        SettingsRow(
          label: l10n.sourceUpdateTitle,
          description: [
            l10n.updateCurrentVersion,
            currentAppVersion.marketing,
            ?source.localCommit,
            switch (source.lastChecked) {
              final time? => l10n.updateLastChecked(_format(context, time)),
              null => l10n.updateNeverChecked,
            },
          ].join(' · '),
          trailing: IdeButton(
            label: l10n.updateCheckNow,
            icon: Codicons.refresh,
            secondary: true,
            onPressed: busy ? null : () => unawaited(source.check()),
          ),
        ),
        if (status != null)
          SettingsRow(
            label: status,
            description: detail,
            trailing: SettingsButtons(
              children: [
                IdeButton(
                  label: l10n.sourceUpdateLog,
                  secondary: true,
                  onPressed: () => unawaited(source.openLog()),
                ),
                if (source.status == SourceUpdateStatus.available ||
                    source.status == SourceUpdateStatus.failed)
                  IdeButton(
                    label: l10n.sourceUpdateUpdateNow,
                    onPressed: busy ? null : () => unawaited(source.update()),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  /// What the last check found, with Restart to Update when it found a
  /// version; null before any.
  Widget? _status(BuildContext context, UpdateService service) {
    final l10n = context.l10n;
    final release = service.release;
    final version = release?.version.marketing ?? '';
    final label = switch (service.status) {
      UpdateStatus.idle => null,
      UpdateStatus.checking => l10n.updateChecking,
      UpdateStatus.upToDate => l10n.updateUpToDate,
      UpdateStatus.available => l10n.updateAvailable(version),
      UpdateStatus.downloading => switch (service.progress) {
        final progress? => l10n.updateDownloadingProgress(
          version,
          (progress * 100).floor(),
        ),
        null => l10n.updateDownloading(version),
      },
      UpdateStatus.ready => l10n.updateReady(version),
      UpdateStatus.failed when release == null => l10n.updateCheckFailed(
        '${service.error}',
      ),
      UpdateStatus.failed => l10n.updateFailed('${service.error}'),
    };
    if (label == null) return null;
    final problem = _problem;
    final details = [
      if (release != null && service.isMandatory(release))
        l10n.updateMandatory(version)
      else if (release != null &&
          service.skippedVersion == '${release.version}')
        l10n.updateSkippedNote,
      if (problem is ManualUpdateRequired)
        l10n.updateManual(problem.reason)
      else if (problem != null)
        l10n.updateFailed('$problem'),
    ];
    return SettingsRow(
      label: label,
      description: details.isEmpty ? null : details.join('\n'),
      trailing: release == null
          ? null
          : SettingsButtons(
              children: [
                if (problem is ManualUpdateRequired)
                  IdeButton(
                    label: l10n.updateOpenDownloadPage,
                    secondary: true,
                    onPressed: () => unawaited(
                      widget.updates!.openUrl(
                        ManualUpdateRequired.downloadPage,
                      ),
                    ),
                  ),
                IdeButton(
                  label: l10n.updateRestartNow,
                  onPressed: service.status == UpdateStatus.downloading
                      ? null
                      : () => unawaited(_restart()),
                ),
              ],
            ),
    );
  }
}
