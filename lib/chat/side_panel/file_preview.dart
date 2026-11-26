import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:bao_editor/monaco/flutter/editor_decorations.dart';
import 'package:bao_editor/monaco/flutter/editor_document_model.dart';
import 'package:bao_editor/monaco/flutter/language_overrides.dart';
import 'package:flutter/gestures.dart' show PointerHoverEvent;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show SelectedContent;
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart'
    show Clipboard, ClipboardData, LogicalKeyboardKey;
import 'package:path/path.dart' as p;
import 'package:super_sliver_list/super_sliver_list.dart';

import '../../base/shown_when_ready.dart';
import '../../base/smooth_scroll.dart';
import '../../ide/editor_word_wrap.dart';
import '../../ide/file_service.dart';
import '../../ide/git/git_annotations.dart';
import '../../ide/git/git_blame.dart'
    show
        IdeGitBlameController,
        formatGitBlame,
        ideGitBlameMargin,
        ideGitBlameTemplate;
import '../../ide/git/git_blame_card.dart';
import '../../ide/git/git_model.dart' show IdeGitBlameInformation;
import '../../ide/git/git_repository.dart';
import '../../ide/ide_agent_edits.dart';
import '../../ide/ide_code_diff.dart';
import '../../ide/ide_code_editor.dart';
import '../../ide/ide_hover.dart';
import '../../ide/ide_image_preview.dart';
import '../../ide/ide_status_bar.dart' show IdeLanguageNames;
import '../../ide/ide_view_state.dart';
import '../../ide/language_mode.dart';
import '../../ide/ide_dialog.dart';
import '../../ide/ide_editor_placeholder.dart'
    show IdeEditorPlaceholder, ideFormatSize;
import '../../ide/markdown/markdown_paste.dart';
import '../../ide/markdown/markdown_preview.dart';
import '../../l10n/l10n.dart';
import '../../platform/app_platform.dart';
import '../../theme/app_theme.dart';
import '../../theme/codicons.dart';
import '../../theme/material_file_icons.dart';
import '../../theme/workbench_theme.dart' show themeColors;
import '../../workspace/editor_launcher.dart' show openExternal;
import '../../workspace/window_controls.dart';
import '../composer/composer_files.dart'
    show CodeReference, ComposerFile, CopiedCode;
import '../composer/file_drop.dart';
import '../widgets/code_citation.dart' show CodeColorizer;
import '../widgets/hover_builder.dart';
import '../widgets/hover_scrollbar.dart';
import 'file_edit.dart';
import 'file_link.dart';
import 'file_open.dart';
import 'line_diff.dart';
import '../../base/safe_selection_indexes.dart';
import '../../ide/host_paths.dart';

/// Shows [commit]'s details in the side panel, as GitLens's card opens
/// one: who made it and when, its parents and files.
typedef ShowCommitDetails = void Function(
  IdeGitRepository git,
  String path,
  String commit,
);

/// A file in the side panel: its text in the IDE's editor, to edit, search
/// and save (Cmd+S, Ctrl+S), the lines asked for marked and scrolled to,
/// the agent's change pending in it ([agentEdit]) shown as the IDE shows it,
/// each part to keep or undo; its changes against the text before the
/// agent changed it, read only; a markdown file rendered (or its text); an
/// image. A bar over it names it, with [actions] (Open in Fast Ide) at its
/// end, after the agent's change's own (see [IdeAgentEditActions]).
class FilePreview extends StatefulWidget {
  const FilePreview({
    super.key,
    required this.request,
    required this.files,
    this.root,
    this.readBytes,
    this.paths,
    this.colorize,
    this.reveal = 0,
    this.onOpenFile,
    this.actions = const [],
    this.language = true,
    this.edit,
    this.onEdit,
    this.highlights,
    this.formatter,
    this.agentEdit,
    this.onOpenAgentChange,
    this.diffScroll,
    this.onDiffScrolled,
    this.viewState = IdeViewState.empty,
    this.onPreviewLeft,
    this.git,
    this.onShowCommit,
  });

  final FileOpenRequest request;

  /// The agent's change pending in the file, shown in its text where it is
  /// edited here.
  final IdeAgentEdit? agentEdit;

  /// Opens the next file whose agent change is pending, at it, once this
  /// one's is all kept or undone (see [IdeAgentHunks.open]).
  final ValueChanged<String>? onOpenAgentChange;

  /// Where its changes were scrolled when shown before, for them to show
  /// there again; told [onDiffScrolled] as they scroll.
  final Offset? diffScroll;
  final ValueChanged<Offset>? onDiffScrolled;

  /// Where the file's tab was left before: its edit, made anew, shows
  /// there, its markdown preview too, unless lines are asked for.
  final IdeViewState viewState;

  /// Told the line at the top of its markdown preview as that goes.
  final ValueChanged<int>? onPreviewLeft;

  /// The file's text as edited already (its tab's), to go on with: read
  /// anew in it where it is not changed.
  final SidePanelFileEdit? edit;

  /// Takes the edit made once the file is read, to keep past the preview;
  /// the preview's own, gone with it, when null.
  final ValueChanged<SidePanelFileEdit>? onEdit;

  /// Where the editor's highlighting is kept past the preview, for its tab
  /// shown again to be colored at once; the editor's own when null.
  final IdeCodeHighlights? highlights;

  /// Formats the file with the project's language servers.
  final IdeTextFormatter? formatter;

  /// Reads it, on the project's host.
  final IdeFileService files;

  /// The Git repository the file is in, whose blame shows beside the line
  /// numbers; none outside a repository.
  final IdeGitRepository? git;

  /// Shows a commit's details: a line's blame, its hash pressed.
  final ShowCommitDetails? onShowCommit;

  /// Where the agent works: the bar names the file from there.
  final String? root;

  /// Reads an image's bytes; this machine's [readFileBytes] when null.
  final Future<Uint8List> Function(String path)? readBytes;

  /// How the host spells paths; this machine's when null.
  final p.Context? paths;
  final CodeColorizer? colorize;

  /// Goes up as the same file is asked for again: scrolls back to the
  /// lines asked for.
  final int reveal;

  /// Opens a file a markdown file's link goes to.
  final ValueChanged<FileOpenRequest>? onOpenFile;

  /// At the end of its bar.
  final List<Widget> actions;

  /// Whether its bar names the file's language, to change it.
  final bool language;

  /// Past this many lines, the text is not colored.
  static const maxColoredLines = 5000;

  /// The lines selected in the file [focus] is in, as its text, its lines
  /// or its changes show it: references to them for the chat (Add
  /// Selection to Chat). None where nothing is, or a markdown file shows
  /// rendered.
  static List<CodeReference> selectedAt(BuildContext? focus) =>
      focus?.findAncestorStateOfType<_FilePreviewState>()?._selectedIn(focus) ??
      const [];

  @override
  State<FilePreview> createState() => _FilePreviewState();
}

sealed class _Loaded {
  const _Loaded();
}

final class _Text extends _Loaded {
  const _Text(this.lines, {this.noOriginal = false});

  final List<String> lines;

  /// Its changes were asked for, but the text before is not known.
  final bool noOriginal;
}

final class _Diff extends _Loaded {
  const _Diff(this.original, this.modified, {this.deleted = false});

  final String original;
  final String modified;
  final bool deleted;
}

final class _Failed extends _Loaded {
  const _Failed(this.error);

  final Object error;
}

class _FilePreviewState extends State<FilePreview> {
  _Loaded? _loaded;

  /// By line (or row, for a diff), in the editor's colors once colored.
  List<List<TextSpan>?> _colors = const [];

  /// A markdown file's text rather than it rendered.
  bool _source = false;

  /// A markdown file's text, rendered: its edit's, as it is edited.
  EditorDocumentModel? _markdown;
  int _load = 0;

  /// Read past the binary and size checks (Open Anyway).
  bool _force = false;

  /// Lets it be shown in place of the file before (see [ShownWhenReady]):
  /// once read.
  VoidCallback? _release;

  /// The file's text in the editor, once read; none for changes.
  SidePanelFileEdit? _edit;

  /// The file's blame, in the repository it is in: shown beside the line
  /// numbers of its editor, none for changes or outside a repository.
  IdeGitAnnotations? _blame;

  /// The blame of the caret's line in its editor, after the line's end (as
  /// VS Code's Git extension shows it).
  late final IdeGitBlameController _lineBlame = IdeGitBlameController()
    ..addListener(_blameChanged);

  /// Whether the caret moved since the file was shown: only then does a
  /// line's blame show (not a caret left at the start).
  bool _navigated = false;

  /// The line whose blame the pointer has been on a while, and where
  /// (global): its commit's details hover by it.
  (int, Offset)? _blameHover;
  Timer? _blameHoverTimer;

  /// Whether the card was pinned by a press, rather than shown by the
  /// pointer resting on the blame: it stays as the pointer leaves.
  bool _blamePinned = false;

  /// The card, to keep it while the pointer is on it.
  final GlobalKey _blameCardKey = GlobalKey();

  /// The text the lines asked for were marked in: unmarked once edited.
  Object? _markedIn;
  final _editor = GlobalKey<IdeCodeEditorState>();

  /// [FilePreview.agentEdit] in the editor, and where it is among its parts.
  IdeAgentDiff? _agent;
  late final _hunks = IdeAgentHunks(
    open: (path) => widget.onOpenAgentChange?.call(path),
  );

  FileOpenRequest get _request => widget.request;

  /// An image shows as it is, its changes too: there is no text to compare.
  bool get _image => ideIsImagePath(_request.path);

  /// A markdown file rendered: its changes too, as the file is after them
  /// (its changes a click away), unless it was deleted.
  bool get _isMarkdown =>
      isMarkdownPath(_request.path) &&
      switch (_loaded) {
        _ when !_request.diff => true,
        _Text() || _Diff(deleted: false) => true,
        _ => false,
      };

  /// The file's own text shows, to edit: not its changes, nor the index's,
  /// nor what is only shown ([FileOpenRequest.readOnly]).
  bool get _editable =>
      !_request.diff && _request.modified == null && !_request.readOnly;

  /// The lines shown, where the file's own text shows rather than edited.
  List<String>? get _shownLines => switch (_loaded) {
    _Text(:final lines) => lines,
    _ => null,
  };

  @override
  void initState() {
    super.initState();
    if (widget.edit case final edit? when _editable) _attach(edit);
    EditorLanguageOverrides.instance.addListener(_languageModesChanged);
    EditorWordWrap.on.addListener(_editChanged);
    IdeLanguageNames.ensureLoaded(() {
      if (mounted) setState(() {});
    });
    _start();
  }

  /// A language picked for a file (Change Language Mode): its lines
  /// colored again; the editor colors its own.
  void _languageModesChanged() {
    if (!mounted) return;
    setState(() {});
    if (_edit == null && !_image) unawaited(_read(++_load));
  }

  void _attach(SidePanelFileEdit edit) {
    _edit = edit..addListener(_editChanged);
    edit.controller.addListener(_caretChanged);
    _syncLineBlame();
  }

  /// Lets go of the edit; disposes it unless its tab keeps it.
  void _detach() {
    _dropAgent();
    final edit = _edit;
    _edit = null;
    if (edit == null) return;
    edit.removeListener(_editChanged);
    edit.controller.removeListener(_caretChanged);
    _lineBlame.clear();
    if (widget.onEdit == null && !identical(edit, widget.edit)) edit.dispose();
  }

  void _editChanged() {
    if (mounted) setState(() {});
  }

  /// The caret moved (or the text changed): the line's blame shows, after
  /// the line.
  void _caretChanged() {
    _navigated = true;
    _syncLineBlame();
  }

  /// Reads the blame of the caret's line again: none outside a repository,
  /// or where the file is not edited here.
  void _syncLineBlame() {
    final git = widget.git;
    final edit = _edit;
    if (git == null || edit == null || !_editable) {
      _lineBlame.clear();
      return;
    }
    _lineBlame.update(
      repository: git,
      path: _request.path,
      model: edit.controller.document,
      selections: edit.controller.selections,
      navigated: _navigated,
    );
  }

  @override
  void didUpdateWidget(FilePreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    final old = oldWidget.request;
    if (old.path != _request.path ||
        old.diff != _request.diff ||
        old.original != _request.original ||
        old.modified != _request.modified ||
        oldWidget.files != widget.files) {
      _blame?.dispose();
      _blame = null;
      _dropMarkdown();
      _detach();
      if (widget.edit case final edit? when _editable) _attach(edit);
      _start();
    } else if (oldWidget.reveal != widget.reveal && !_image) {
      // Asked for again (the agent wrote it again, say): read anew, what
      // shows kept until then.
      unawaited(_read(++_load));
    }
    // The repository is found after the panel opens (its folders scanned):
    // the blame shows as soon as it is known.
    if (!identical(oldWidget.git, widget.git)) {
      _blame?.dispose();
      _blame = null;
      _syncBlame(_shownLines);
      _syncLineBlame();
    }
  }

  @override
  void dispose() {
    EditorLanguageOverrides.instance.removeListener(_languageModesChanged);
    EditorWordWrap.on.removeListener(_editChanged);
    _blameHoverTimer?.cancel();
    _blame?.dispose();
    _lineBlame.dispose();
    _dropMarkdown();
    _detach();
    _hunks.dispose();
    _ready();
    super.dispose();
  }

  /// [FilePreview.agentEdit] in the editor of the file's text, as long as
  /// both are there.
  IdeAgentDiff? _syncAgent() {
    final edit = _edit;
    final agentEdit = widget.agentEdit;
    if (edit == null || agentEdit == null || !_editable) {
      _dropAgent();
      return null;
    }
    if (_agent case final agent?
        when identical(agent.controller, edit.controller)) {
      return agent..edit = agentEdit;
    }
    _dropAgent();
    return _agent = IdeAgentDiff(
      agentEdit,
      edit.controller,
      onChanged: _agentChanged,
      save: () async {
        await edit.save();
        if (edit.dirty && edit.error != null) throw edit.error!;
      },
      view: () => _editor.currentState?.view,
      hunks: _hunks,
    );
  }

  void _dropAgent() {
    _agent?.dispose();
    _agent = null;
  }

  /// The change's diff computed anew, its original highlighted: shown,
  /// after the build if in one.
  void _agentChanged() {
    if (!mounted) return;
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() {});
      });
      return;
    }
    setState(() {});
  }

  /// The rendered markdown's own text let go of; not its edit's.
  void _dropMarkdown() {
    if (!identical(_markdown, _edit?.controller.document)) {
      _markdown?.dispose();
    }
    _markdown = null;
  }

  void _start({bool force = false}) {
    _force = force;
    _navigated = false;
    final load = ++_load;
    _loaded = null;
    _colors = const [];
    // The agent's change shows in the text.
    if (_request.agentChange && isMarkdownPath(_request.path)) _source = true;
    _dropMarkdown();
    if (_image) return;
    // Its tab's edit shows as it is while the file is read anew.
    if (_edit case final edit?) {
      _loaded = const _Text([]);
      if (_isMarkdown) _markdown = edit.controller.document;
    } else {
      _release ??= ShownWhenReady.hold(context);
    }
    unawaited(_read(load));
  }

  void _ready() {
    _release?.call();
    _release = null;
  }

  Future<void> _read(int load) async {
    final request = _request;
    String? text;
    Object? error;
    try {
      text =
          await (request.modified?.call() ??
              widget.files.read(request.path, force: _force));
    } catch (e) {
      error = e;
    }
    String? original;
    if (request.diff) {
      try {
        original = await request.original?.call();
      } catch (_) {
        original = null;
      }
    }
    if (!mounted || load != _load) return;
    // A diff holds it back itself, until compared and colored.
    _ready();
    final _Loaded loaded;
    if (request.diff && original != null) {
      if (text == null && error is! IdeFileNotFoundException) {
        loaded = _Failed(error!);
      } else {
        loaded = _Diff(original, text ?? '', deleted: text == null);
      }
    } else if (text == null) {
      loaded = _Failed(error!);
    } else {
      loaded = _Text(diffLines(text), noOriginal: request.diff);
    }
    setState(() {
      _loaded = loaded;
      if (_editable && text != null) _edited(text);
      if (_isMarkdown && text != null) {
        _dropMarkdown();
        _markdown = _edit?.controller.document ?? EditorDocumentModel(text);
      }
    });
    _syncBlame(loaded is _Text ? loaded.lines : null);
    if (_edit != null) return _reveal();
    unawaited(_colorize(load, loaded, original, text));
  }

  /// The file's [text], read: in its edit, made now unless there is one.
  void _edited(String text) {
    if (_edit case final edit?) return edit.reload(text);
    final edit = SidePanelFileEdit(
      path: _request.path,
      files: widget.files,
      text: text,
    );
    // Where it was left; the lines asked for, if any, shown after.
    final view = widget.viewState;
    if (view.selections case final kept?
        when kept.isNotEmpty &&
            kept.every((s) => s.isValid && s.end <= text.length)) {
      edit.controller.setSelections(kept);
    }
    edit.controller.viewState = view.editor;
    _attach(edit);
    widget.onEdit?.call(edit);
  }

  /// The file's blame, beside its lines: its own text, saved, in a Git
  /// repository; [lines] where it shows read-only, none for its changes
  /// shown in their place.
  void _syncBlame([List<String>? lines]) {
    final git = widget.git;
    if (git == null || _request.diff || _request.modified != null) return;
    final document =
        _edit?.controller.document ??
        switch (lines) {
          final lines? when !_editable => EditorDocumentModel(lines.join('\n')),
          _ => null,
        };
    if (document == null || _blame != null) return;
    _blame = IdeGitAnnotations(
      repository: git,
      path: _request.path,
      document: document,
    )..addListener(_blameChanged);
  }

  void _blameChanged() {
    if (!mounted) return;
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() {});
      });
      return;
    }
    setState(() {});
  }

  void _hideBlameHover() {
    _blameHoverTimer?.cancel();
    _blamePinned = false;
    if (_blameHover != null) setState(() => _blameHover = null);
  }

  /// Shows the commit of the blame the pointer is on, once it rests there.
  void _blameHoverAt(int? line, Offset global) {
    // Pinned by a press: it stays where it is.
    if (_blamePinned) return;
    // Already shown for the line: kept where it was put.
    if (_blameHover?.$1 == line) return;
    _blameHoverTimer?.cancel();
    if (line == null) return _hideBlameHover();
    _blameHoverTimer = Timer(ideHoverDelay, () {
      if (mounted) setState(() => _blameHover = (line, global));
    });
  }

  /// Puts the card away once the pointer had a moment to reach it.
  void _hideBlameHoverSoon() {
    _blameHoverTimer?.cancel();
    if (_blameHover == null || _blamePinned) return;
    _blameHoverTimer = Timer(const Duration(milliseconds: 250), () {
      if (!mounted || _blamePinned) return;
      setState(() => _blameHover = null);
    });
  }

  /// Whether [global] is on the card.
  bool _onBlameCard(Offset global) {
    final box = _blameCardKey.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return false;
    return (box.localToGlobal(Offset.zero) & box.size).contains(global);
  }

  /// Whether [global] is on a line with a caret's blame.
  bool _onBlameLine(Offset global) {
    final view = _editor.currentState?.view;
    final box = _editor.currentState?.surfaceBox;
    if (view == null || box == null) return false;
    final local = box.globalToLocal(global);
    for (final line in _lineBlame.lines) {
      if (view.lineRectAt(line.lineNumber)?.contains(local) ?? false) {
        return true;
      }
    }
    return false;
  }

  /// Shows the commit of the blame at [line] at once, where it was pressed;
  /// pressed again, it goes.
  void _pinBlame(int line, Offset global) {
    _blameHoverTimer?.cancel();
    setState(() {
      if (_blamePinned && _blameHover?.$1 == line) {
        _blamePinned = false;
        _blameHover = null;
        return;
      }
      _blamePinned = true;
      _blameHover = (line, global);
    });
  }

  /// [commit]'s author, when, and subject, as GitLens writes a line's
  /// blame.
  String _blameText(BuildContext context, IdeGitBlameInformation commit) =>
      formatGitBlame(ideGitBlameTemplate, commit, l10n: context.l10n);

  /// As wide as [blame]'s longest text, in the code's size.
  double _blameTextWidth(
    BuildContext context,
    IdeGitAnnotations blame,
    int lineCount,
  ) {
    var longest = blame.loaded ? '' : '0000/00/00';
    for (var line = 1; line <= lineCount; line++) {
      if (blame.at(line) case final commit?) {
        final text = _blameText(context, commit);
        if (text.length > longest.length) longest = text;
      }
    }
    final measure = TextPainter(
      text: TextSpan(text: longest, style: _codeStyle(context)),
      textDirection: TextDirection.ltr,
      textScaler: _codeScaler(context),
    )..layout();
    final width = measure.width;
    measure.dispose();
    return width;
  }

  /// The commit of the blame hovered (or pressed), by the pointer, as
  /// GitLens's card shows it.
  Widget? _blameHoverCard() {
    final hover = _blameHover;
    if (hover == null) return null;
    final (line, global) = hover;
    final commit = _commitAt(line);
    final box = context.findRenderObject();
    if (commit == null || box is! RenderBox) return null;
    final local = box.globalToLocal(global);
    // Inside the panel: under the line, or over it by the panel's bottom.
    final width = math.min(460.0, math.max(240.0, box.size.width - 16));
    final left = math.min(local.dx + 12, box.size.width - width - 8);
    final below = local.dy < box.size.height - 220;
    return Positioned(
      left: math.max(8, left),
      top: below ? local.dy + 12 : null,
      bottom: below ? null : box.size.height - local.dy + 12,
      // The card's own presses are not the editor's, and the pointer
      // resting on it keeps it: its hash and copying can be used.
      child: MouseRegion(
        onHover: (_) => _blameHoverTimer?.cancel(),
        onExit: (_) => _hideBlameHoverSoon(),
        child: IdeGitBlameCard(
          key: _blameCardKey,
          commit: commit,
          width: width,
          onCopy: () =>
              unawaited(Clipboard.setData(ClipboardData(text: commit.hash))),
          // Its hash shows the commit's details, in the file's repository
          // (not the project's, which a nested repository is out of); the
          // panel's own card goes.
          onOpenCommit: switch (widget.git) {
            final git?
                when widget.onShowCommit != null && !commit.uncommitted =>
              () {
                _hideBlameHover();
                widget.onShowCommit!(git, _request.path, commit.hash);
              },
            _ => null,
          },
        ),
      ),
    );
  }

  /// [line]'s commit: the caret's line's in the editor, else the file's
  /// blame as saved.
  IdeGitBlameInformation? _commitAt(int line) {
    for (final blame in _lineBlame.lines) {
      if (blame.lineNumber == line) return blame.commit;
    }
    return _blame?.at(line);
  }

  /// The caret's lines' blame, after their ends (as VS Code's Git extension
  /// shows it): who last changed each, when, and in which commit.
  List<EditorDecoration> _lineBlameDecorations(BuildContext context) {
    final lines = _lineBlame.lines;
    final snapshot = _edit?.controller.document.snapshot;
    if (lines.isEmpty || snapshot == null) return const [];
    final color = themeColors['git.blame.editorDecorationForeground'];
    return [
      for (final line in lines)
        if (line.lineNumber <= snapshot.lineCount)
          EditorDecoration(
            start: snapshot.contentEnds[line.lineNumber - 1],
            end: snapshot.contentEnds[line.lineNumber - 1],
            afterText: switch (line.commit) {
              final commit? => _blameText(context, commit),
              null => context.l10n.gitBlameNotCommittedYet,
            },
            afterColor: color,
            afterMargin: ideGitBlameMargin,
          ),
    ];
  }

  /// Shows the commit of the blame the pointer is on, once it rests there:
  /// the text painted past the end of a line with a caret, where the
  /// editor paints it.
  void _inlineBlameHovered(PointerHoverEvent event) {
    if (_blamePinned) return;
    final line = _inlineBlameLineAt(event.position);
    if (line != null) return _blameHoverAt(line, event.position);
    // On the line, or on the card to reach: kept.
    if (_onBlameLine(event.position) || _onBlameCard(event.position)) {
      _blameHoverTimer?.cancel();
      return;
    }
    _hideBlameHoverSoon();
  }

  /// A press on the blame past a line's end: its commit's details there,
  /// as GitLens shows them; a press anywhere else puts them away.
  void _inlineBlamePressed(PointerDownEvent event) {
    final line = _inlineBlameLineAt(event.position);
    if (line == null) {
      if (_blameHover != null) _hideBlameHover();
      return;
    }
    if (_commitAt(line) == null) return;
    _pinBlame(line, event.position);
  }

  /// The line of the blame painted at [global] (a line with a caret's),
  /// where the editor paints it: none when the pointer is not on one.
  int? _inlineBlameLineAt(Offset global) {
    final lines = _lineBlame.lines;
    final view = _editor.currentState?.view;
    final box = _editor.currentState?.surfaceBox;
    final snapshot = _edit?.controller.document.snapshot;
    if (lines.isEmpty || view == null || box == null || snapshot == null) {
      return null;
    }
    final local = box.globalToLocal(global);
    for (final line in lines) {
      if (line.commit == null || line.lineNumber > snapshot.lineCount) {
        continue;
      }
      final caret = view.caretRectAt(snapshot.contentEnds[line.lineNumber - 1]);
      if (caret == null) continue;
      final start = caret.right + ideGitBlameMargin;
      if (local.dy < caret.top ||
          local.dy >= caret.bottom ||
          local.dx < start - 8 ||
          local.dx > start + 640) {
        continue;
      }
      return line.lineNumber;
    }
    return null;
  }

  /// The lines asked for, from their first's start to their last's end,
  /// in the edit's text; none when none were.
  (int, int)? get _range {
    final range = _request.range;
    final snapshot = _edit?.controller.document.snapshot;
    if (range == null || snapshot == null) return null;
    final count = snapshot.lineStarts.length;
    final first = (range.start - 1).clamp(0, count - 1);
    final last = (range.end - 1).clamp(first, count - 1);
    return (snapshot.lineStarts[first], snapshot.contentEnds[last]);
  }

  /// Marks the lines asked for and scrolls to them, the caret at their
  /// start; the agent's change's part asked for, unmarked.
  void _reveal() {
    final edit = _edit;
    if (edit != null && _request.agentChange) {
      _markedIn = null;
      if (_isMarkdown && !_source) setState(() => _source = true);
      _hunks.reveal(line: _request.range?.start);
      return;
    }
    final range = _range;
    if (edit == null || range == null) return;
    final (start, end) = range;
    _markedIn = edit.controller.document.snapshot;
    edit.controller.select(start, start);
    // Once built, the first time.
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _editor.currentState?.revealRange(start, end),
    );
  }

  Future<void> _colorize(
    int load,
    _Loaded loaded,
    String? original,
    String? text,
  ) async {
    final colorize = widget.colorize;
    if (colorize == null) return;
    final path = _request.path;
    Future<List<List<TextSpan>>?> colors(String? code) async {
      if (code == null || code.isEmpty) return null;
      if (diffLines(code).length > FilePreview.maxColoredLines) return null;
      try {
        return await colorize(path, code);
      } catch (_) {
        return null;
      }
    }

    final List<List<TextSpan>?> byRow;
    switch (loaded) {
      case _Text(:final lines):
        final now = await colors(text);
        if (now == null) return;
        byRow = [for (var i = 0; i < lines.length; i++) now.elementAtOrNull(i)];
      // The diff editor highlights its own.
      case _Diff() || _Failed():
        return;
    }
    if (!mounted || load != _load) return;
    setState(() => _colors = byRow);
  }

  @override
  Widget build(BuildContext context) {
    _syncAgent();
    return ColoredBox(
      color: AppColors.code,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _bar(context),
              ?_notice(context),
              Expanded(child: _body(context)),
            ],
          ),
          ?_blameHoverCard(),
        ],
      ),
    );
  }

  Widget _bar(BuildContext context) {
    final l10n = context.l10n;
    final paths = widget.paths ?? p.context;
    final root = widget.root;
    final path = _request.path;
    final shown = root != null && paths.isWithin(root, path)
        ? paths.relative(path, from: root)
        : path;
    final range = _request.range;
    return Container(
      height: 30,
      padding: const EdgeInsets.only(left: 12, right: 6),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.partBorder)),
      ),
      child: Row(
        children: [
          FileIcon(path, size: 14),
          const SizedBox(width: 6),
          Expanded(
            // The whole path, which the bar may cut short.
            child: IdeHover(
              message: path,
              followMouse: true,
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(text: shown),
                    if (range != null &&
                        !_request.diff &&
                        !_request.agentChange)
                      TextSpan(
                        text: '  ${range.label}',
                        style: TextStyle(color: AppColors.textFaint),
                      ),
                  ],
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: AppColors.textMuted, fontSize: 12),
              ),
            ),
          ),
          if (!_image && widget.language)
            _TextButton(
              label: IdeLanguageNames.forPath(path),
              tooltip: l10n.languageModeChange,
              onPressed: () => unawaited(changeLanguageMode(context, path)),
            ),
          if (_isMarkdown && _markdown != null)
            _TextButton(
              label: _source
                  ? l10n.sidePanelPreview
                  : _loaded is _Diff
                  ? l10n.sidePanelChanges
                  : l10n.sidePanelSource,
              onPressed: () => setState(() => _source = !_source),
            ),
          if ((widget.agentEdit, _agent) case (final edit?, _?)
              when !_isMarkdown || _source)
            IdeAgentEditActions(edit: edit, hunks: _hunks),
          // Its lines, the editor's or only shown, wrapped or not: the
          // editors' one setting.
          if (_loaded is _Text && !_image && (_markdown == null || _source))
            IdeActionButton(
              icon: Codicons.wordWrap,
              tooltip: l10n.menuWordWrap,
              checked: EditorWordWrap.on.value,
              onPressed: EditorWordWrap.toggle,
            ),
          ...widget.actions,
        ],
      ),
    );
  }

  Widget? _notice(BuildContext context) {
    final l10n = context.l10n;
    final text = switch (_loaded) {
      _ when _edit?.error != null => localizedFileError(l10n, _edit!.error!),
      _Text(noOriginal: true) => l10n.sidePanelNoOriginal,
      _Diff(deleted: true) => l10n.sidePanelDeleted,
      _Diff(:final original, :final modified) when original == modified =>
        l10n.sidePanelUnchanged,
      _ => null,
    };
    if (text == null) return null;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      color: AppColors.surface,
      child: Text(
        text,
        style: TextStyle(color: AppColors.textMuted, fontSize: 12),
      ),
    );
  }

  Widget _body(BuildContext context) {
    if (_image) {
      return IdeImagePreview(path: _request.path, read: widget.readBytes);
    }
    switch (_loaded) {
      case null:
        return const SizedBox.shrink();
      case _Failed(:final error):
        // As the IDE's editor shows it.
        return IdeEditorPlaceholder(
          error: error,
          path: _request.path,
          onOpenAnyway: () => setState(() => _start(force: true)),
          onRetry: () => setState(_start),
          // This machine's files only, not a remote project's host's, and
          // the file itself, not another version of it.
          onOpenInDefaultApp:
              widget.files is! IdeHostFiles &&
                  WindowControls.canOpenInDefaultApp &&
                  _request.modified == null
              ? () => unawaited(openExternal(_request.path))
              : null,
        );
      case _Text() || _Diff() when _markdown != null && !_source:
        return _markdownPreview(_markdown!);
      case _Diff(:final original, :final modified, :final deleted):
        return IdeCodeDiff(
          // Asked for again: scrolled back to the lines asked for.
          key: ValueKey(('diff', _request.path, widget.reveal)),
          path: _request.path,
          original: original,
          modified: modified,
          line: _request.range?.start,
          scrolled: widget.diffScroll,
          onScrolled: widget.onDiffScrolled,
          highlights: widget.highlights,
          git: widget.git,
          commitId: _request.commitId,
          // Lines of the file as it is now.
          onCopy: deleted
              ? null
              : (text, start, end) => _copied(start, end, text),
        );
      case _Text(:final lines):
        if (_edit case final edit?) return _editing(context, edit);
        final range = _request.range;
        final gutter = _gutter(context, lines.length);
        final wrap = EditorWordWrap.on.value;
        final blame = _blame;
        final blameWidth = blame == null || blame.empty
            ? 0.0
            : _blameTextWidth(context, blame, lines.length) +
                  ideGitBlameMargin +
                  24;
        return _Lines(
          key: ValueKey(('text', _request.path)),
          count: lines.length,
          wrap: wrap,
          lineHeight: _lineHeight(context),
          reveal: widget.reveal,
          target: range == null ? null : range.start - 1,
          width:
              _widthOf(context, lines, () => lines) + gutter + blameWidth + 20,
          onCopy: (first, last, text) => _copied(first + 1, last + 1, text),
          row: (context, i, sideways, current) {
            final commit = current && blameWidth > 0 ? blame?.at(i + 1) : null;
            return _LineRow(
              number: i + 1,
              text: lines[i],
              colors: _colors.elementAtOrNull(i),
              gutter: gutter,
              blame: commit == null ? null : _blameText(context, commit),
              blameColor: themeColors['git.blame.editorDecorationForeground'],
              onBlameHover: commit == null
                  ? null
                  : (global) => _blameHoverAt(i + 1, global),
              onBlameTap: commit == null
                  ? null
                  : (global) => _pinBlame(i + 1, global),
              sideways: sideways,
              wrap: wrap,
              marked:
                  range != null && i + 1 >= range.start && i + 1 <= range.end,
            );
          },
        );
    }
  }

  /// A markdown file rendered: its own text, edited here as in its source;
  /// its changes', as it is after them, only shown.
  Widget _markdownPreview(EditorDocumentModel model) {
    // The file's own text, its edit's: edited here, as in its source.
    final edit = _edit;
    final editable =
        edit != null &&
        !_request.agentChange &&
        identical(model, edit.controller.document);
    final preview = IdeMarkdownPreview(
      key: _previewKey,
      path: _request.path,
      model: model,
      readBytes: widget.readBytes ?? readFileBytes,
      pathContext: widget.paths,
      readOnly: !editable,
      // Its source's editor told, which keeps whether it is saved.
      onEdited: edit?.controller.syncFromDocument,
      // Pictures and files pasted: copied beside it, linked to.
      onPaste: editable ? () => _markdownPaste().paste(_request.path) : null,
      initialLine: _request.range?.start ?? widget.viewState.previewLine,
      onLeave: (line) {
        if (line != null) widget.onPreviewLeft?.call(line);
      },
      onOpenFile: _openLinked,
      onOpenExternal: (uri) => unawaited(openExternal(uri.toString())),
      // This machine's files only, not a remote project's host's.
      onReveal:
          widget.files is! IdeHostFiles && WindowControls.canRevealInFileManager
          ? (path) => unawaited(WindowControls.revealInFileManager(path))
          : null,
    );
    if (!editable) return preview;
    // Files dropped on it from other apps: as pasted, where they are
    // let go.
    return _saved(
      edit,
      FileDropRegion(delegate: _markdownDrop, child: preview),
    );
  }

  /// [child], where [edit] is edited, saving it with the IDE's keys.
  Widget _saved(SidePanelFileEdit edit, Widget child) => CallbackShortcuts(
    bindings: {
      AppPlatform.isMacOS
          ? const SingleActivator(LogicalKeyboardKey.keyS, meta: true)
          : const SingleActivator(LogicalKeyboardKey.keyS, control: true): () =>
          unawaited(edit.save()),
    },
    child: child,
  );

  /// The file's text in the IDE's editor, the lines asked for marked until
  /// it is edited; saved with the IDE's keys.
  Widget _editing(BuildContext context, SidePanelFileEdit edit) {
    final range = _range;
    final marked =
        range != null &&
        !_request.agentChange &&
        identical(_markedIn, edit.controller.document.snapshot);
    return _saved(
      edit,
      // The blame past a line's end is painted, not a widget: a press on it
      // is taken here, before the editor takes it as a press on the line.
      Listener(
        onPointerDown: _inlineBlamePressed,
        child: MouseRegion(
          onHover: _inlineBlameHovered,
          onExit: (_) {
            // A moment to reach the card.
            if (!_blamePinned) _hideBlameHoverSoon();
          },
          child: IdeCodeEditor(
            key: _editor,
            controller: edit.controller,
            path: _request.path,
            highlights: widget.highlights,
            interfaceSized: false,
            formatter: widget.formatter,
            agent: _agent,
            decorations: [
              ..._lineBlameDecorations(context),
              if (marked)
                EditorDecoration(
                  start: range.$1,
                  end: range.$2,
                  isWholeLine: true,
                  backgroundColor:
                      themeColors['editor.rangeHighlightBackground'],
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// What [FilePreview.selectedAt] finds at [focus], in it.
  List<CodeReference> _selectedIn(BuildContext focus) {
    List<CodeReference> of(
      Iterable<({String text, int startLine, int endLine})> lines,
    ) => [
      for (final (:text, :startLine, :endLine) in lines)
        CodeReference(
          path: _request.path,
          start: startLine,
          end: endLine,
          code: text,
        ),
    ];

    switch (_loaded) {
      case _Text() || _Diff() when _markdown != null && !_source:
        return const [];
      // Lines of the file as it is now: none of one deleted.
      case _Diff(deleted: false):
        final diff = focus.findAncestorStateOfType<IdeCodeDiffState>();
        return of(diff?.selectedLines() ?? const []);
      case _Text():
        if (_edit case final edit?) return of(edit.controller.selectedLines());
        final lines = focus.findAncestorStateOfType<_LinesState>();
        final rows = lines?._selection.selectedRows();
        if (rows == null) return const [];
        return of([
          (text: rows.text, startLine: rows.first + 1, endLine: rows.last + 1),
        ]);
      default:
        return const [];
    }
  }

  /// Lines [start] to [end] copied, as [text]: pasted into the chat's
  /// composer, they go in as a reference to those lines of the file, as
  /// the IDE's editor's do.
  void _copied(int start, int end, String text) => CopiedCode.record(
    path: _request.path,
    start: start,
    end: end,
    code: text,
  );

  // --- A markdown file's pastes and drops ------------------------------------------

  /// Its preview: a new one for another file, or the same asked for again
  /// (scrolled back to the lines asked for).
  GlobalKey<IdeMarkdownPreviewState> get _previewKey {
    final shows = (_request.path, widget.reveal);
    if (shows != _previewShows) {
      _previewShows = shows;
      _previewKeyNow = GlobalKey();
    }
    return _previewKeyNow;
  }

  (String, int)? _previewShows;
  GlobalKey<IdeMarkdownPreviewState> _previewKeyNow = GlobalKey();

  /// Pastes and drops of pictures and files: copied beside the file (to
  /// the project's host, a remote one), as the IDE's preview does.
  MarkdownPaste _markdownPaste() {
    final l10n = context.l10n;
    final files = widget.files;
    final remote = files is IdeHostFiles;
    return MarkdownPaste(
      files: files,
      l10n: l10n,
      root: widget.root,
      context:
          widget.paths ??
          (remote ? hostPathsFor(widget.root ?? '') : p.context),
      remote: remote,
      confirmLarge: (name, size) async {
        if (!mounted) return false;
        final pick = await showIdeDialog(
          context,
          type: IdeDialogType.question,
          message: l10n.markdownPasteLargeTitle,
          detail: l10n.markdownPasteLargeMessage(name, ideFormatSize(size)),
          buttons: [l10n.markdownPasteLargeConfirm],
        );
        return pick == 0;
      },
      report: (message) {
        if (!mounted) return;
        unawaited(
          showIdeDialog(
            context,
            type: IdeDialogType.error,
            message: message,
            buttons: const [],
            cancel: l10n.commonOk,
          ),
        );
      },
    );
  }

  late final _markdownDrop = _MarkdownDrop((position, files) async {
    final path = _request.path;
    final outcome = await _markdownPaste().drop(path, files);
    if (!mounted || outcome is! MarkdownPasteLinks) return;
    if (_previewKeyNow.currentState case final preview?
        when _request.path == path) {
      preview.insert(outcome.text, position: position);
    }
  });

  /// A link in a markdown file: to a file beside it.
  void _openLinked(String path, String? fragment) {
    final range = fragment == null
        ? null
        : FileLink.parseHref('x#$fragment')?.range;
    widget.onOpenFile?.call(FileOpenRequest(path, range: range));
  }

  static TextStyle _codeStyle(BuildContext context) =>
      AppFonts.codeStyle(12).copyWith(height: 1.5);

  static TextScaler _codeScaler(BuildContext context) =>
      MediaQuery.textScalerOf(context);

  /// The actual height of one source line, including the configured scaler.
  static double _lineHeight(BuildContext context) {
    final painter = TextPainter(
      text: TextSpan(text: 'M', style: _codeStyle(context)),
      textDirection: TextDirection.ltr,
      textScaler: _codeScaler(context),
    )..layout();
    final height = painter.height;
    painter.dispose();
    return height;
  }

  /// The line numbers' width, for [count] lines.
  static double _gutter(BuildContext context, int count) {
    final painter = TextPainter(
      text: TextSpan(text: '$count', style: _codeStyle(context)),
      textDirection: TextDirection.ltr,
      textScaler: _codeScaler(context),
    )..layout();
    final width = painter.width + 16;
    painter.dispose();
    return width;
  }

  /// [_width] of [shown]'s lines, kept while they, the font and its scale
  /// are the same: laying out every line of a long file again on each
  /// build (the chat beside it streaming) made it crawl.
  double _widthOf(
    BuildContext context,
    Object shown,
    Iterable<String> Function() lines,
  ) {
    final key = (shown, _codeStyle(context), _codeScaler(context));
    if (_measured case (final kept, final width) when kept == key) {
      return width;
    }
    final width = _width(context, lines());
    _measured = (key, width);
    return width;
  }

  ((Object, TextStyle, TextScaler), double)? _measured;

  /// As wide as the widest rendered line, including wide fallback glyphs.
  /// Only those that may be the widest are laid out: a line's width, in
  /// the code font's columns, is at least its characters and at most a
  /// wide glyph two columns, so no line under half the longest's estimate
  /// can be wider than it.
  static double _width(BuildContext context, Iterable<String> lines) {
    final style = _codeStyle(context);
    final painter = TextPainter(
      textDirection: TextDirection.ltr,
      textScaler: _codeScaler(context),
    );
    int columns(String line) {
      var n = 0;
      for (final unit in line.codeUnits) {
        n += unit == 0x09 ? 4 : (unit < 0x80 ? 1 : 2);
      }
      return n;
    }

    final estimates = [for (final line in lines) (line, columns(line))];
    final most = estimates.fold(0, (most, e) => math.max(most, e.$2));
    var width = 0.0;
    for (final (line, estimate) in estimates) {
      if (line.isEmpty || estimate * 2 < most) continue;
      painter.text = TextSpan(
        text: line.replaceAll('\t', '    '),
        style: style,
      );
      painter.layout();
      width = math.max(width, painter.width);
    }
    painter.dispose();
    return width;
  }
}

/// The lines, built as they come into view, scrolled to [target] (a
/// row, from 0) first and as [reveal] goes up; sideways, as wide as
/// [width] needs.
///
/// Copied, the lines selected go one to a line, and [onCopy] hears which
/// rows (from 0, the first and the last) they are.
class _Lines extends StatefulWidget {
  const _Lines({
    super.key,
    required this.count,
    required this.row,
    required this.width,
    required this.lineHeight,
    this.wrap = false,
    this.target,
    this.reveal = 0,
    this.onCopy,
  });

  final int count;

  /// Whether long lines wrap at the view's width, rather than scroll
  /// sideways: rows as tall as they wrap.
  final bool wrap;
  final Widget Function(
    BuildContext context,
    int index,
    ScrollController sideways,
    bool current,
  )
  row;
  final double width;
  final double lineHeight;
  final int? target;
  final int reveal;
  final void Function(int first, int last, String text)? onCopy;

  @override
  State<_Lines> createState() => _LinesState();
}

class _LinesState extends State<_Lines> {
  final _scroll = SmoothScrollController();
  final _sideways = ScrollController();

  /// The row the pointer is on (or the one asked for): the one whose blame
  /// shows, as a caret's line's does in the editor.
  late int? _current = widget.target;

  /// Where each row is, wrapped: rows of their own heights.
  final _list = ListController();
  late final _selection = _LinesSelection(
    (first, last, text) => widget.onCopy?.call(first, last, text),
  );

  @override
  void initState() {
    super.initState();
    _reveal();
  }

  @override
  void didUpdateWidget(_Lines oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.reveal != widget.reveal ||
        oldWidget.target != widget.target ||
        oldWidget.wrap != widget.wrap ||
        oldWidget.lineHeight != widget.lineHeight) {
      if (oldWidget.target != widget.target) _current = widget.target;
      _reveal();
    }
  }

  /// A few lines over the target, once laid out.
  void _reveal() {
    final target = widget.target;
    if (target == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      if (widget.wrap) {
        if (_list.isAttached) {
          _list.jumpToItem(
            index: math.max(0, target - 3),
            scrollController: _scroll,
            alignment: 0,
          );
        }
        return;
      }
      final position = _scroll.position;
      final offset = (target - 3) * widget.lineHeight;
      _scroll.jumpTo(offset.clamp(0.0, position.maxScrollExtent));
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    _sideways.dispose();
    _list.dispose();
    _selection.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // The measured width already includes gutters and change markers.
        final width = math.max(constraints.maxWidth, widget.width + 24);
        Widget row(BuildContext context, int index) => MouseRegion(
          onHover: (_) {
            if (_current != index) setState(() => _current = index);
          },
          child: _SelectableRow(
            index: index,
            lines: _selection,
            child: widget.row(context, index, _sideways, index == _current),
          ),
        );
        const padding = EdgeInsets.symmetric(vertical: 6);
        // Both scrollbars at the edges of the view, not of the lines as
        // wide as the longest; drawn as the editor's are.
        return SelectionArea(
          child: SelectionContainer(
            delegate: _selection,
            child: ScrollbarTheme(
              data: _editorScrollbars(context),
              child: HoverScrollbar(
                controller: _scroll,
                thickness: 14,
                notificationPredicate: (notification) =>
                    notification.metrics.axis == Axis.vertical,
                child: widget.wrap
                    ? SuperListView.builder(
                        controller: _scroll,
                        listController: _list,
                        padding: padding,
                        itemCount: widget.count,
                        itemBuilder: row,
                      )
                    : HoverScrollbar(
                        controller: _sideways,
                        thickness: 12,
                        notificationPredicate: (notification) =>
                            notification.metrics.axis == Axis.horizontal,
                        child: SingleChildScrollView(
                          controller: _sideways,
                          scrollDirection: Axis.horizontal,
                          child: SizedBox(
                            width: width,
                            height: constraints.maxHeight,
                            child: ListView.builder(
                              controller: _scroll,
                              padding: padding,
                              itemExtent: widget.lineHeight,
                              itemCount: widget.count,
                              itemBuilder: row,
                            ),
                          ),
                        ),
                      ),
              ),
            ),
          ),
        );
      },
    );
  }

  /// The editor's sliders (`EditorScrollbarPainter`): square, edge to edge,
  /// at least 20 long, in `scrollbarSlider.*` as hovered and dragged.
  static ScrollbarThemeData _editorScrollbars(BuildContext context) =>
      ScrollbarTheme.of(context).copyWith(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) =>
              themeColors[states.contains(WidgetState.dragged)
                  ? 'scrollbarSlider.activeBackground'
                  : states.contains(WidgetState.hovered)
                  ? 'scrollbarSlider.hoverBackground'
                  : 'scrollbarSlider.background'],
        ),
        radius: Radius.zero,
        crossAxisMargin: 0,
        mainAxisMargin: 0,
        minThumbLength: 20,
      );
}

/// The selection of [_Lines]: what is selected of each row, one to a line
/// (each row's text is a selection of its own, which the list would run
/// together), and which rows, told as it is copied.
class _LinesSelection extends StaticSelectionContainerDelegate
    with SafeSelectionIndexes {
  _LinesSelection(this.onCopy);

  final void Function(int first, int last, String text) onCopy;

  /// The rows' selected text, as each row gives it while it is asked for.
  final List<(int, String)> _rows = [];

  @override
  SelectedContent? getSelectedContent() {
    final (content, rows) = _selectedContent();
    if (rows == null) return content;
    onCopy(rows.first, rows.last, rows.text);
    return SelectedContent(plainText: rows.text);
  }

  /// The rows selected (from 0) and their text, one to a line; null when
  /// none is.
  ({int first, int last, String text})? selectedRows() => _selectedContent().$2;

  (SelectedContent?, ({int first, int last, String text})?) _selectedContent() {
    _rows.clear();
    final content = super.getSelectedContent();
    // The rows outside the selection tell nothing selected: not its own.
    final rows = [
      for (final row in _rows)
        if (row.$2.isNotEmpty) row,
    ]..sort((a, b) => a.$1.compareTo(b.$1));
    _rows.clear();
    if (content == null || rows.isEmpty) return (content, null);
    // An empty line selects nothing of its own: kept, between the others.
    final byRow = {for (final (row, text) in rows) row: text};
    final text = [
      for (var row = rows.first.$1; row <= rows.last.$1; row++)
        byRow[row] ?? '',
    ].join('\n');
    return (content, (first: rows.first.$1, last: rows.last.$1, text: text));
  }
}

/// The row [index] of [_Lines], whose selected text it tells [lines].
class _SelectableRow extends StatefulWidget {
  const _SelectableRow({
    required this.index,
    required this.lines,
    required this.child,
  });

  final int index;
  final _LinesSelection lines;
  final Widget child;

  @override
  State<_SelectableRow> createState() => _SelectableRowState();
}

class _SelectableRowState extends State<_SelectableRow> {
  late final _selection = _RowSelection(widget);

  @override
  void didUpdateWidget(_SelectableRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    _selection.row = widget;
  }

  @override
  void dispose() {
    _selection.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      SelectionContainer(delegate: _selection, child: widget.child);
}

class _RowSelection extends StaticSelectionContainerDelegate
    with SafeSelectionIndexes {
  _RowSelection(this.row);

  _SelectableRow row;

  @override
  SelectedContent? getSelectedContent() {
    final content = super.getSelectedContent();
    if (content != null) row.lines._rows.add((row.index, content.plainText));
    return content;
  }
}

/// One line: its number and its text, on the editor's range highlight
/// where it is among the lines asked for.
class _LineRow extends StatelessWidget {
  const _LineRow({
    required this.number,
    required this.text,
    required this.gutter,
    required this.sideways,
    this.colors,
    this.marked = false,
    this.wrap = false,
    this.blame,
    this.blameColor,
    this.onBlameHover,
    this.onBlameTap,
  });

  final int number;
  final String text;
  final double gutter;
  final ScrollController sideways;

  /// Wrapped at the row's width, as many lines as that takes; else one.
  final bool wrap;
  final List<TextSpan>? colors;
  final bool marked;

  /// The line's blame, past the end of it; none without one.
  final String? blame;
  final Color? blameColor;
  final ValueChanged<Offset>? onBlameHover;
  final ValueChanged<Offset>? onBlameTap;

  @override
  Widget build(BuildContext context) {
    final style = AppFonts.codeStyle(12).copyWith(height: 1.5);
    final background = marked
        ? themeColors['editor.rangeHighlightBackground']
        : Colors.transparent;
    final shown = text.replaceAll('\t', '    ');
    final textStyle = style.copyWith(color: themeColors['editor.foreground']);
    // The blame, past the line's end: as wide as the line is (one line).
    double? blameLeft;
    if (blame != null && !wrap) {
      final measure = TextPainter(
        text: TextSpan(text: shown, style: textStyle),
        textDirection: TextDirection.ltr,
        textScaler: MediaQuery.textScalerOf(context),
        maxLines: 1,
      )..layout();
      blameLeft = gutter + 20 + measure.width + ideGitBlameMargin;
      measure.dispose();
    }
    return ColoredBox(
      color: background,
      child: Stack(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: gutter + 20),
              Expanded(
                child: Text.rich(
                  TextSpan(
                    children: colors,
                    text: colors == null ? shown : null,
                  ),
                  maxLines: wrap ? null : 1,
                  softWrap: wrap,
                  overflow: wrap ? null : TextOverflow.clip,
                  style: textStyle,
                ),
              ),
            ],
          ),
          if (blameLeft != null)
            Positioned(
              left: blameLeft,
              top: 0,
              bottom: 0,
              child: _BlameInline(
                text: blame!,
                color: blameColor,
                onHover: onBlameHover,
                onTap: onBlameTap,
                style: style,
              ),
            ),
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            child: AnimatedBuilder(
              animation: sideways,
              builder: (context, child) => Transform.translate(
                offset: Offset(sideways.hasClients ? sideways.offset : 0, 0),
                child: child,
              ),
              // Keep the line numbers visible while the source scrolls
              // underneath them.
              child: ColoredBox(
                color: Color.alphaBlend(background, AppColors.code),
                child: SelectionContainer.disabled(
                  child: SizedBox(
                    width: gutter + 20,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: gutter,
                          child: Text(
                            '$number',
                            textAlign: TextAlign.right,
                            style: style.copyWith(
                              color: marked
                                  ? themeColors['editorLineNumber.activeForeground']
                                  : themeColors['editorLineNumber.foreground'],
                            ),
                          ),
                        ),
                        const SizedBox(width: 20),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A line's blame past the end of it in [_Lines]: who last changed it,
/// when, and in which commit; its commit's details on hover, pinned by a
/// press.
class _BlameInline extends StatelessWidget {
  const _BlameInline({
    required this.text,
    required this.style,
    this.color,
    this.onHover,
    this.onTap,
  });

  final String text;
  final TextStyle style;
  final Color? color;
  final ValueChanged<Offset>? onHover;
  final ValueChanged<Offset>? onTap;

  @override
  Widget build(BuildContext context) {
    Widget cell = Align(
      alignment: Alignment.centerLeft,
      heightFactor: 1,
      child: Text(
        text,
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.fade,
        style: style.copyWith(color: color),
      ),
    );
    if (onHover != null || onTap != null) {
      cell = MouseRegion(
        cursor: onTap == null ? MouseCursor.defer : SystemMouseCursors.click,
        onHover: onHover == null ? null : (event) => onHover!(event.position),
        child: Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: onTap == null
              ? null
              : (event) => onTap!(event.position),
          child: cell,
        ),
      );
    }
    return cell;
  }
}

/// A button in the bar named by its [label], as the IDE's status bar's:
/// the file's language (a click changes it), a markdown file's Edit or
/// Preview. [tooltip] over it when given.
class _TextButton extends StatelessWidget {
  const _TextButton({
    required this.label,
    required this.onPressed,
    this.tooltip,
  });

  final String label;
  final String? tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final button = HoverBuilder(
      cursor: SystemMouseCursors.click,
      builder: (context, hovered) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onPressed,
        child: Container(
          height: 22,
          padding: const EdgeInsets.symmetric(horizontal: 6),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: hovered ? themeColors['toolbar.hoverBackground'] : null,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            label,
            style: TextStyle(color: AppColors.textMuted, fontSize: 12),
          ),
        ),
      ),
    );
    if (tooltip case final message?) {
      return IdeHover(message: message, child: button);
    }
    return button;
  }
}

/// Files dropped on a markdown file's preview (see
/// [_FilePreviewState._markdownDrop]).
class _MarkdownDrop implements FileDropDelegate {
  _MarkdownDrop(this.onDrop);

  final void Function(Offset position, List<ComposerFile> files) onDrop;

  @override
  void fileDragOver(Offset position, List<ComposerFile> files) {}

  @override
  void fileDragLeave() {}

  @override
  void fileDrop(Offset position, List<ComposerFile> files) =>
      onDrop(position, files);
}
