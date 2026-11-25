// New (not a port): the local end of ZMODEM, driven by a scripted peer.
//
// The receiver here answers like lrzsz, including the ZRPOS restarts that
// used to start a second read loop on the same RandomAccessFile
// ("An async operation is currently pending").
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:baocode/ide/terminal/terminal_zmodem.dart';
import 'package:flutter_test/flutter_test.dart';

const _zpad = 0x2a;
const _zdle = 0x18;
const _zbin = 0x41;
const _zhex = 0x42;
const _zrqinit = 0;
const _zrinit = 1;
const _zfile = 4;
const _zfin = 8;
const _zrpos = 9;
const _zdata = 10;
const _zeof = 11;
const _zcrce = 0x68;
const _zcrCG = 0x69;
const _zcrcW = 0x6b;

void main() {
  late Directory temp;
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('baocode-zmodem');
  });
  tearDown(() async {
    if (temp.existsSync()) await temp.delete(recursive: true);
  });

  test('a ZRPOS in the middle of an upload restarts without racing', () async {
    final bytes = Uint8List(300 * 1024);
    for (var index = 0; index < bytes.length; index++) {
      bytes[index] = (index * 37 + 11) & 0xff;
    }
    final path = '${temp.path}/sample.bin';
    await File(path).writeAsBytes(bytes);
    final done = Completer<void>();
    final peer = _UploadPeer();
    late final ZmodemSession session;
    session = ZmodemSession(
      send: (out) {
        peer.add(out);
        peer.answer(session);
      },
      writeOutput: (_) {},
      pickSaveFile: (_) async => null,
      pickFiles: () async => [path],
      onChanged: () {},
      onDone: () {
        if (!done.isCompleted) done.complete();
      },
    );
    peer.attach(session);
    // Restart from scratch once, then rewind twice more mid-stream.
    peer.restarts = const [
      _Restart(afterBytes: 8192, at: 0),
      _Restart(afterBytes: 60000, at: 20000),
      _Restart(afterBytes: 200000, at: 100000),
    ];
    session.feed(_hexHeader(_zrinit, const [0, 0, 0, 3]));
    await done.future.timeout(const Duration(seconds: 20));
    expect(session.status.error, isNull);
    expect(session.status.finishedFiles, 1);
    expect(peer.eofOffsets, [bytes.length]);
    expect(peer.content, equals(bytes));
  });

  test('rewinding mid-download truncates and rewrites in place', () async {
    final bytes = Uint8List(64 * 1024);
    for (var index = 0; index < bytes.length; index++) {
      bytes[index] = (index * 53 + 7) & 0xff;
    }
    final path = '${temp.path}/received.bin';
    final done = Completer<void>();
    final peer = _DownloadPeer();
    late final ZmodemSession session;
    session = ZmodemSession(
      send: (out) => peer.add(out, session),
      writeOutput: (_) {},
      pickSaveFile: (_) async => path,
      pickFiles: () async => const [],
      onChanged: () {},
      onDone: () {
        if (!done.isCompleted) done.complete();
      },
    );
    peer.bytes = bytes;
    peer.rewindAt = 32 * 1024;
    session.feed(_hexHeader(_zrqinit, const [0, 0, 0, 0]));
    await done.future.timeout(const Duration(seconds: 20));
    expect(session.status.error, isNull);
    expect(await File(path).readAsBytes(), equals(bytes));
  });
}

class _Restart {
  const _Restart({required this.afterBytes, required this.at});
  final int afterBytes;
  final int at;
}

/// Answers an upload like `rz`: asks for positions and acknowledges frames.
class _UploadPeer {
  final List<int> content = [];
  final List<int> eofOffsets = [];
  final List<int> _input = [];
  List<_Restart> restarts = const [];
  int _nextRestart = 0;
  int _seen = 0;
  _Expect _expect = _Expect.header;
  bool _done = false;
  ZmodemSession? _session;

  void attach(ZmodemSession session) => _session = session;

  void add(Uint8List bytes) {
    _input.addAll(bytes);
    _pump();
  }

  void answer(ZmodemSession session) {
    if (_done || _nextRestart >= restarts.length) return;
    final restart = restarts[_nextRestart];
    if (_seen < restart.afterBytes) return;
    _nextRestart++;
    session.feed(_hexHeader(_zrpos, _le32(restart.at)));
  }

  void _pump() {
    while (!_done) {
      final parsed = _expect == _Expect.header ? _takeHeader() : _takeData();
      if (!parsed) return;
    }
  }

  bool _takeHeader() {
    if (_input.length >= 2 && _input[0] == 0x4f && _input[1] == 0x4f) {
      _input.removeRange(0, 2);
      _done = true;
      return false;
    }
    final header = _readHeader(_input);
    if (header == null) return false;
    _expect = _Expect.header;
    switch (header.type) {
      case _zfile:
        _expect = _Expect.fileInfo;
      case _zdata:
        final offset = _u32le(header.data);
        if (offset > content.length) {
          throw StateError('ZDATA past the received bytes: $offset');
        }
        content.length = offset;
        _expect = _Expect.data;
      case _zeof:
        eofOffsets.add(_u32le(header.data));
        _session?.feed(_hexHeader(_zrinit, const [0, 0, 0, 3]));
      case _zfin:
        _session?.feed(_hexHeader(_zfin, const [0, 0, 0, 0]));
    }
    return true;
  }

  bool _takeData() {
    final subpacket = _readSubpacket(_input);
    if (subpacket == null) return false;
    if (_expect == _Expect.data) {
      content.addAll(subpacket.payload);
      _seen += subpacket.payload.length;
      if (subpacket.frameEnd == _zcrce) _expect = _Expect.header;
    } else {
      _expect = _Expect.header;
      // Like rz: ask for the file once its info arrives.
      _session?.feed(_hexHeader(_zrpos, _le32(0)));
    }
    return true;
  }
}

/// Answers a download like `sz`: sends the file after ZRPOS and rewinds once.
class _DownloadPeer {
  late Uint8List bytes;
  int rewindAt = -1;
  final List<int> _input = [];
  final List<int> _output = [];
  bool _sentInfo = false;
  bool _sentData = false;
  bool _sentFin = false;

  void add(Uint8List data, ZmodemSession session) {
    _input.addAll(data);
    while (true) {
      final header = _readHeader(_input);
      if (header == null) return;
      switch (header.type) {
        case _zrinit:
          if (!_sentInfo) {
            _sentInfo = true;
            _sendFileInfo();
          } else if (!_sentFin) {
            _sentFin = true;
            _output.addAll(_hexHeader(_zfin, const [0, 0, 0, 0]));
          }
        case _zrpos:
          if (!_sentData) {
            _sentData = true;
            _sendPrefix();
            // Rewind into the part just sent; the session must truncate
            // before writing the next subpacket.
            _sendRest(rewindAt - 8192);
          }
      }
      session.feed(Uint8List.fromList(_output));
      _output.clear();
    }
  }

  void _sendFileInfo() {
    final info = utf8.encode('received.bin\x00${bytes.length} 0 100644\x00');
    _output
      ..addAll(_binaryHeader(_zfile, const [0, 0, 0, 1]))
      ..addAll(_subpacket(info, _zcrcW));
  }

  void _sendPrefix() {
    _output.addAll(_binaryHeader(_zdata, _le32(0)));
    _output.addAll(_subpacket(bytes.sublist(0, rewindAt), _zcrce));
  }

  void _sendRest(int offset) {
    _output.addAll(_binaryHeader(_zdata, _le32(offset)));
    var at = offset;
    while (at < bytes.length) {
      final end = at + 8192 < bytes.length ? at + 8192 : bytes.length;
      final last = end == bytes.length;
      _output.addAll(
        _subpacket(bytes.sublist(at, end), last ? _zcrce : _zcrCG),
      );
      at = end;
    }
    _output.addAll(_hexHeader(_zeof, _le32(bytes.length)));
  }
}

enum _Expect { header, fileInfo, data }

class _Header {
  const _Header(this.type, this.data);
  final int type;
  final List<int> data;
}

class _Subpacket {
  const _Subpacket(this.payload, this.frameEnd);
  final List<int> payload;
  final int frameEnd;
}

_Header? _readHeader(List<int> input) {
  while (input.isNotEmpty &&
      (input.first == 0x0d ||
          input.first == 0x0a ||
          input.first == 0x8a ||
          input.first == 0x11)) {
    input.removeAt(0);
  }
  if (input.length < 4) return null;
  if (input[0] == _zpad &&
      input[1] == _zpad &&
      input[2] == _zdle &&
      input[3] == _zhex) {
    if (input.length < 18) return null;
    final values = <int>[];
    for (var index = 4; index < 18; index += 2) {
      values.add((_hexValue(input[index])! << 4) | _hexValue(input[index + 1])!);
    }
    var end = 18;
    while (end < input.length &&
        (input[end] == 0x0d ||
            input[end] == 0x0a ||
            input[end] == 0x8a ||
            input[end] == 0x11)) {
      end++;
    }
    input.removeRange(0, end);
    return _Header(values.first, values.sublist(1, 5));
  }
  if (input[0] == _zpad && input[1] == _zdle && input[2] == _zbin) {
    final values = <int>[];
    var index = 3;
    while (values.length < 7) {
      if (index >= input.length) return null;
      final byte = input[index++];
      if (byte == _zdle) {
        if (index >= input.length) return null;
        values.add(input[index++] ^ 0x40);
      } else {
        values.add(byte);
      }
    }
    input.removeRange(0, index);
    return _Header(values.first, values.sublist(1, 5));
  }
  throw StateError('unexpected bytes: ${input.take(8).toList()}');
}

_Subpacket? _readSubpacket(List<int> input) {
  var end = -1;
  var frameEnd = 0;
  for (var index = 0; index + 1 < input.length; index++) {
    if (input[index] == _zdle) {
      final next = input[index + 1];
      if (next >= _zcrce && next <= _zcrcW) {
        end = index;
        frameEnd = next;
        break;
      }
    }
  }
  if (end < 0) return null;
  final crc = <int>[];
  var index = end + 2;
  while (crc.length < 2) {
    if (index >= input.length) return null;
    final byte = input[index++];
    if (byte == _zdle) {
      if (index >= input.length) return null;
      crc.add(input[index++] ^ 0x40);
    } else {
      crc.add(byte);
    }
  }
  final payload = _unescape(input.sublist(0, end));
  final expected = _crc16([...payload, frameEnd]);
  if (expected != ((crc[0] << 8) | crc[1])) {
    throw StateError('bad data subpacket CRC');
  }
  input.removeRange(0, index);
  return _Subpacket(payload, frameEnd);
}

Uint8List _hexHeader(int type, List<int> data) {
  final values = [type, ...data];
  final crc = _crc16(values);
  final body = [...values, crc >> 8, crc & 0xff];
  final hex = body.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return Uint8List.fromList([
    _zpad,
    _zpad,
    _zdle,
    _zhex,
    ...ascii.encode(hex),
    0x0d,
    0x0a,
    0x11,
  ]);
}

Uint8List _binaryHeader(int type, List<int> data) {
  final values = [type, ...data];
  final crc = _crc16(values);
  return Uint8List.fromList([
    _zpad,
    _zdle,
    _zbin,
    ..._escape([...values, crc >> 8, crc & 0xff], 0),
  ]);
}

Uint8List _subpacket(List<int> payload, int frameEnd) {
  final crc = _crc16([...payload, frameEnd]);
  return Uint8List.fromList([
    ..._escape(payload, 0),
    _zdle,
    frameEnd,
    ..._escape([crc >> 8, crc & 0xff], frameEnd),
  ]);
}

List<int> _escape(List<int> bytes, int previous) {
  final result = <int>[];
  for (final byte in bytes) {
    final escape =
        byte == _zdle ||
        byte == 0x10 ||
        byte == 0x90 ||
        byte == 0x11 ||
        byte == 0x91 ||
        byte == 0x13 ||
        byte == 0x93 ||
        byte == 0x0d ||
        byte == 0x8d ||
        ((byte == 0x40 || byte == 0xc0) &&
            (previous == 0x40 || previous == 0xc0));
    if (escape) {
      result
        ..add(_zdle)
        ..add(byte ^ 0x40);
    } else {
      result.add(byte);
    }
    previous = byte;
  }
  return result;
}

List<int> _unescape(List<int> bytes) {
  final result = <int>[];
  for (var index = 0; index < bytes.length; index++) {
    final byte = bytes[index];
    if (byte == _zdle && index + 1 < bytes.length) {
      result.add(bytes[++index] ^ 0x40);
    } else {
      result.add(byte);
    }
  }
  return result;
}

List<int> _le32(int value) => [
  value & 0xff,
  (value >> 8) & 0xff,
  (value >> 16) & 0xff,
  (value >> 24) & 0xff,
];

int _u32le(List<int> bytes) =>
    bytes[0] | (bytes[1] << 8) | (bytes[2] << 16) | (bytes[3] << 24);

int? _hexValue(int byte) {
  if (byte >= 0x30 && byte <= 0x39) return byte - 0x30;
  if (byte >= 0x61 && byte <= 0x66) return byte - 0x61 + 10;
  if (byte >= 0x41 && byte <= 0x46) return byte - 0x41 + 10;
  return null;
}

final Uint32List _crcTable = () {
  final table = Uint32List(256);
  for (var index = 0; index < 256; index++) {
    var value = index << 8;
    for (var bit = 0; bit < 8; bit++) {
      value = (value & 0x8000) != 0
          ? ((value << 1) ^ 0x1021) & 0xffff
          : (value << 1) & 0xffff;
    }
    table[index] = value;
  }
  return table;
}();

int _crc16(List<int> bytes) {
  var crc = 0;
  for (final byte in bytes) {
    crc = (_crcTable[((crc >> 8) ^ byte) & 0xff] ^ (crc << 8)) & 0xffff;
  }
  return crc;
}
