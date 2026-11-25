import 'dart:io';

import 'package:baocode/update/source_update_controller.dart';
import 'package:baocode/update/version.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory data;
  late SourceUpdateController source;

  setUp(() async {
    data = await Directory.systemTemp.createTemp('baocode-source-update');
    source = SourceUpdateController(
      sourceDir: data.path,
      logPath: '${data.path}/update.log',
      autoUpdate: () => false,
    )..localVersion = AppVersion.parse('2.0.6+39');
  });

  tearDown(() async {
    source.dispose();
    await data.delete(recursive: true);
  });

  test('a version upstream publishes is an update', () {
    source.upstreamVersion = AppVersion.parse('2.0.7+40');
    expect(source.hasNewVersion, isTrue);
  });

  test('the same version is not, whatever the commits', () {
    source.upstreamVersion = AppVersion.parse('2.0.6+39');
    source.upstreamCommits = 12;
    expect(source.hasNewVersion, isFalse);
  });

  test('an older version is not', () {
    source.upstreamVersion = AppVersion.parse('2.0.5+38');
    expect(source.hasNewVersion, isFalse);
  });

  test('a build number alone is', () {
    source.upstreamVersion = AppVersion.parse('2.0.6+40');
    expect(source.hasNewVersion, isTrue);
  });

  test('nothing published yet is not', () {
    expect(source.hasNewVersion, isFalse);
  });
}
