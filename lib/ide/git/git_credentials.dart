// Credentials for a Git remote that asks for them: VS Code's askpass, in
// the window instead of a terminal there is none of. Git runs with
// GIT_TERMINAL_PROMPT=0, so an HTTPS remote that needs a user name and a
// password fails with "could not read Username for 'https://…': terminal
// prompts disabled"; the window asks, and the command runs again with the
// credentials as a request header for that host alone.

import 'dart:async';
import 'dart:convert';

import 'package:bao_remote/git.dart';

/// A user name and a password (or access token) for a Git host.
class IdeGitCredential {
  const IdeGitCredential(this.username, this.password);

  final String username;
  final String password;
}

/// The window's answers to Git's prompts, once per host and run.
class IdeGitCredentials {
  IdeGitCredentials._();

  static final IdeGitCredentials instance = IdeGitCredentials._();

  /// Asks for [host]'s credentials (`https://172.16.11.238`); null where
  /// there is no window to ask in, and the command's failure stands.
  Future<IdeGitCredential?> Function(String host)? prompter;

  final Map<String, IdeGitCredential> _known = {};
  final Map<String, Future<IdeGitCredential?>> _asking = {};

  /// The host of an HTTPS remote [output] could not ask for, or null where
  /// the failure is not about credentials.
  static String? hostIn(IdeGitOutput output) {
    if (output.exitCode == 0) return null;
    final text = '${output.stderr}\n${output.stdout}';
    for (final pattern in _hostPatterns) {
      final match = pattern.firstMatch(text);
      if (match case final match?) return _origin(match.group(1)!);
    }
    return null;
  }

  static final _hostPatterns = [
    RegExp(r"could not read (?:Username|Password) for '(https?://[^']+)'"),
    RegExp(r"Authentication failed for '(https?://[^']+)'"),
  ];

  /// `https://host` for [url], without the path or the credentials in it.
  static String _origin(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.host.isEmpty) return url;
    final port = uri.hasPort ? ':${uri.port}' : '';
    return '${uri.scheme}://${uri.host}$port';
  }

  /// Git's arguments that send [credential] to [origin]'s requests only:
  /// `git -c http.https://host/.extraHeader=Authorization: Basic … …`.
  static List<String> arguments(String origin, IdeGitCredential credential) {
    final token = base64Encode(
      utf8.encode('${credential.username}:${credential.password}'),
    );
    return ['-c', 'http.$origin/.extraHeader=Authorization: Basic $token'];
  }

  /// [origin]'s credentials: those given before, or the prompter's; null
  /// where none were given.
  Future<IdeGitCredential?> forHost(String origin) {
    if (_known[origin] case final known?) return Future.value(known);
    if (_asking[origin] case final asking?) return asking;
    final prompter = this.prompter;
    if (prompter == null) return Future.value();
    final asking = prompter(origin)
        .then((credential) {
          if (credential != null) _known[origin] = credential;
          return credential;
        })
        // Not the removed future itself: `whenComplete` would wait on it.
        .whenComplete(() {
          _asking.remove(origin);
        });
    _asking[origin] = asking;
    return asking;
  }

  /// Forgets [origin]'s, after they were refused.
  void forget(String origin) => _known.remove(origin);

  /// Forgets every host's (the tests', and a window's on its way out).
  void clear() {
    _known.clear();
    _asking.clear();
  }
}
