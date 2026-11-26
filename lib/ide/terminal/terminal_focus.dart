// Where the keyboard is, when it is a shell's: the window's keys ask this
// before running a command, so a terminal keeps Ctrl+W, Ctrl+A and the
// other control characters the shell reads.
import 'dart:collection';

abstract final class TerminalFocus {
  /// The terminals whose shell has the focus (a mirror of one can show
  /// without it).
  static final _focused = LinkedHashSet<Object>.identity();

  /// Whether any terminal's shell has the keyboard.
  static bool get active => _focused.isNotEmpty;

  static void enter(Object terminal) => _focused.add(terminal);

  static void leave(Object terminal) => _focused.remove(terminal);
}
