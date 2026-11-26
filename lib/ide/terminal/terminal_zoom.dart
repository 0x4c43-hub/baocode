import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../settings/user_settings.dart';
import '../../theme/code_font.dart';

/// Zooming a terminal with Ctrl (⌘ on macOS too) and the wheel: the text
/// size settings.json keeps as `terminal.integrated.fontSize`, the one
/// Settings → Appearance picks, so every terminal follows and it holds
/// across windows and runs.
abstract final class TerminalZoom {
  static const settingKey = CodeFont.terminalSizeSettingKey;

  static UserSettings? _settings;

  /// Keeps what is zoomed from now on in [settings].
  static void follow(UserSettings settings) => _settings = settings;

  /// The size one notch from [current]: a point larger scrolling up (a
  /// wheel's [delta] is negative then), a point smaller down, between
  /// [CodeFont.minSize] and [CodeFont.maxSize].
  static double next(double current, double delta) {
    final step = current.roundToDouble() + (delta < 0 ? 1 : -1);
    return step.clamp(CodeFont.minSize, CodeFont.maxSize).toDouble();
  }

  /// Draws the terminals at [size] now, and keeps it.
  static void set(double size) {
    CodeFont.terminalSize.value = size;
    final settings = _settings;
    if (settings == null) return;
    unawaited(
      settings
          .update(settingKey, CodeFont.terminalSizeSetting(size))
          .catchError(
            // A settings file that does not parse is left as it is; the size
            // holds for the run.
            (Object error) => debugPrint('$settingKey not kept: $error'),
          ),
    );
  }
}
