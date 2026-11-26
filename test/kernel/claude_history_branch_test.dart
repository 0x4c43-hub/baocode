import 'dart:convert';
import 'dart:io';

import 'package:baocode/kernel/agent_kernel.dart';
import 'package:baocode/kernel/claude_code/claude_storage.dart';
import 'package:flutter_test/flutter_test.dart';

/// A line of a session file: [type] at [uuid], after [parent].
Map<String, Object?> _line(
  String type,
  String uuid, {
  String? parent,
  String? subtype,
  Object? content,
}) => {
  'type': type,
  'uuid': uuid,
  'parentUuid': ?parent,
  'subtype': ?subtype,
  'timestamp': '2026-11-26T02:52:34.096Z',
  'message': {'content': content ?? []},
};

void main() {
  late Directory folder;
  late File file;

  setUp(() async {
    folder = await Directory.systemTemp.createTemp('claude-history-');
    file = File('${folder.path}/session.jsonl');
  });

  tearDown(() => folder.delete(recursive: true));

  Future<List<Object?>> readTypes({int turns = 10}) async {
    final page = await ClaudeStorage.readPage(
      SessionRecord(
        id: 's',
        title: 't',
        updatedAt: DateTime(2026),
        cwd: folder.path,
        path: file.path,
      ),
      turns: turns,
    );
    return [for (final entry in page.entries) entry['uuid']];
  }

  test(
    'a note about a failed request does not hide the turns before it',
    () async {
      // What a session whose requests failed while it ran looks like: the
      // error's parent is the last message the API had answered, and the
      // turns after it are branched off that message, not off the error.
      final lines = [
        _line('user', 'u1', content: 'first'),
        _line('assistant', 'a1', parent: 'u1'),
        _line('user', 'u2', parent: 'a1', content: 'second'),
        _line('assistant', 'a2', parent: 'u2'),
        _line('system', 'e1', parent: 'a1', subtype: 'api_error'),
      ];
      file.writeAsStringSync(
        [for (final line in lines) jsonEncode(line)].join('\n'),
      );

      expect(await readTypes(), ['u1', 'a1', 'u2', 'a2']);
    },
  );

  test('a compaction boundary stays part of the branch', () async {
    final lines = [
      _line('user', 'u1', content: 'first'),
      _line('assistant', 'a1', parent: 'u1'),
      _line('system', 'b1', parent: 'a1', subtype: 'compact_boundary'),
      _line('user', 'u2', parent: 'b1', content: 'second'),
      _line('assistant', 'a2', parent: 'u2'),
    ];
    file.writeAsStringSync(
      [for (final line in lines) jsonEncode(line)].join('\n'),
    );

    expect(await readTypes(), ['u1', 'a1', 'b1', 'u2', 'a2']);
  });
}
