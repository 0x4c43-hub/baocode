import 'dart:io';
import 'dart:convert';

/// Whether this is the local "BaoCode 2" build.
///
/// `tool/build_macos.dart` passes `--dart-define=BAOCODE_CUSTOM=true`: the
/// build has its own bundle identifier and must not install BaoCode's
/// official updates, which would replace it with the original app.
///
/// The define alone would be missed by `flutter run` and by a plain
/// `flutter build macos`; those still build this project's bundle
/// identifier, so the running bundle is checked as well.
final bool customEdition = _builtAsCustom || _runningThisBundle;

const _builtAsCustom = bool.fromEnvironment('BAOCODE_CUSTOM');

/// This build's bundle identifier, and the Finder extension's under it.
const appBundleId = 'dev.baocode.desktop.baocode2';
const finderExtensionId = '$appBundleId.FinderExtension';

/// The checkout this build came from (`tool/build_macos.dart` passes it):
/// its `tool/sync_custom.sh` takes what upstream publishes. Empty for a
/// build made another way, which then updates nothing.
const sourceDir = String.fromEnvironment('BAOCODE_SOURCE_DIR');

/// Whether the app that is running was built from this project.
bool get _runningThisBundle {
  if (!Platform.isMacOS) return false;
  final executable = Platform.resolvedExecutable;
  if (executable.contains('BaoCode 2.app/Contents/MacOS/')) return true;
  // `<bundle>.app/Contents/MacOS/<executable>`: the Info.plist beside it
  // names the bundle. The identifier is a plain string in both plist
  // encodings, so search the bytes rather than parse the plist.
  try {
    final contents = File(executable).parent.parent;
    final plist = File('${contents.path}/Info.plist').readAsBytesSync();
    return _contains(plist, utf8.encode(appBundleId));
  } on Object {
    return false;
  }
}

bool _contains(List<int> haystack, List<int> needle) {
  if (needle.isEmpty) return true;
  for (var i = 0; i + needle.length <= haystack.length; i++) {
    var matches = true;
    for (var j = 0; j < needle.length; j++) {
      if (haystack[i + j] != needle[j]) {
        matches = false;
        break;
      }
    }
    if (matches) return true;
  }
  return false;
}
