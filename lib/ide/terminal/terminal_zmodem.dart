/*---------------------------------------------------------------------------------------------
 *  Copyright (c) Microsoft Corporation. All rights reserved.
 *  Licensed under the MIT License. See License.txt in the project root for license information.
 *--------------------------------------------------------------------------------------------*/

// ZMODEM (rz/sz) in a terminal: the local end of the protocol, speaking for
// the emulator over the pseudo terminal's byte stream.
//
// The file follows the wire format of lrzsz (the de facto implementation):
// hex headers for ZRQINIT/ZRINIT/ZRPOS/ZEOF/ZFIN, binary 16-bit CRC headers
// for ZFILE/ZDATA, and data subpackets whose CRC covers the payload and the
// frame-end byte. Only the CRC16 form is sent, which every receiver accepts;
// CRC32 frames are still parsed.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:path/path.dart' as p;

/// Which way the files go, from the point of view of this computer.
enum ZmodemDirection { download, upload }

/// What a transfer is doing, for the terminal's progress display.
class ZmodemStatus {
  const ZmodemStatus({
    required this.active,
    required this.direction,
    required this.name,
    required this.fileIndex,
    required this.fileCount,
    required this.transferred,
    required this.total,
    required this.waitingForUser,
    required this.error,
    required this.savedPath,
    required this.finishedFiles,
  });

  final bool active;
  final ZmodemDirection? direction;
  final String? name;
  final int fileIndex;
  final int fileCount;
  final int transferred;
  final int total;
  final bool waitingForUser;
  final String? error;
  final String? savedPath;
  final int finishedFiles;
}

/// One ZMODEM session (`sz` or `rz` on the other end of the terminal).
///
/// [feed] takes what the process printed; [send] writes to the process;
/// [pickSaveFile] and [pickFiles] ask the user for local paths. The session
/// is a state machine: it stays quiet between frames and hands anything that
/// is not ZMODEM back through [writeOutput] so the terminal still shows the
/// program's messages.
class ZmodemSession {
  ZmodemSession({
    required this.send,
    required this.writeOutput,
    required this.pickSaveFile,
    required this.pickFiles,
    required this.onChanged,
    this.onDone,
    this.limits = const ZmodemLimits(),
  });

  /// Writes bytes to the process, unencoded (already in wire format).
  final void Function(Uint8List bytes) send;

  /// Writes bytes that are not part of the protocol to the screen.
  final void Function(Uint8List bytes) writeOutput;

  /// Local path to save [name] to; null when the user cancels.
  final Future<String?> Function(String name) pickSaveFile;

  /// Local files to send; empty when the user cancels.
  final Future<List<String>> Function() pickFiles;

  /// Something changed that the progress display shows.
  final void Function() onChanged;

  /// The session ended, for any reason.
  final void Function()? onDone;

  final ZmodemLimits limits;

  bool _active = true;
  bool get active => _active;

  ZmodemDirection? _direction;
  ZmodemDirection? get direction => _direction;

  String? _name;
  String? get name => _name;

  int _fileIndex = 0;
  int get fileIndex => _fileIndex;

  int _fileCount = 1;
  int get fileCount => _fileCount;

  int _transferred = 0;
  int get transferred => _transferred;

  int _total = 0;
  int get total => _total;

  int _finishedFiles = 0;
  int get finishedFiles => _finishedFiles;

  bool _waitingForUser = false;
  bool get waitingForUser => _waitingForUser;

  String? _error;
  String? get error => _error;

  String? _savedPath;
  String? get savedPath => _savedPath;

  ZmodemStatus get status => ZmodemStatus(
    active: _active,
    direction: _direction,
    name: _name,
    fileIndex: _fileIndex,
    fileCount: _fileCount,
    transferred: _transferred,
    total: _total,
    waitingForUser: _waitingForUser,
    error: _error,
    savedPath: _savedPath,
    finishedFiles: _finishedFiles,
  );

  Uint8List _buffer = Uint8List(0);
  bool _draining = false;
  Timer? _idle;

  // What comes after the last header.
  _SubpacketExpectation? _expect;
  bool _dataCrc32 = false;

  // Receiving (`sz` on the other end).
  RandomAccessFile? _download;
  String? _downloadPath;
  int _offset = 0;
  bool _discardData = false;
  bool _gotFin = false;

  // Sending (`rz` on the other end).
  final List<String> _files = [];
  int _nextFile = 0;
  RandomAccessFile? _upload;
  int _uploadSize = 0;
  _SendPhase _sendPhase = _SendPhase.idle;
  // At most one loop reads [_upload] at a time: a dart:io RandomAccessFile
  // throws "An async operation is currently pending" when two reads (or a
  // read and a close) overlap on the same handle. A ZRPOS that arrives while
  // data is going out only records where to resume; the running loop picks
  // it up at the next chunk boundary.
  Future<void>? _uploadLoop;
  int? _uploadRestart;
  int _uploadGeneration = 0;

  // The receiver's ZRINIT asked for control characters to be escaped.
  bool _escapeCtl = false;

  /// Takes [data] from the process. Returns bytes left over once the session
  /// is over (the peer's closing "OO", say), or null while it runs.
  Uint8List? feed(Uint8List data) {
    if (!_active) return data;
    _buffer = Uint8List.fromList([..._buffer, ...data]);
    _drain();
    _resetIdle();
    if (_active) return null;
    var rest = _buffer;
    _buffer = Uint8List(0);
    if (_direction == ZmodemDirection.download &&
        rest.length >= 2 &&
        rest[0] == 0x4f &&
        rest[1] == 0x4f) {
      rest = rest.sublist(2);
    }
    return rest;
  }

  /// Stops the transfer, telling the other end to abort.
  void cancel() {
    if (!_active) return;
    _sendHeader(_zabort);
    send(Uint8List.fromList(const [0x18, 0x18, 0x18, 0x18, 0x18]));
    _finish(error: 'cancelled');
  }

  /// Releases the session without telling the other end (the terminal went
  /// away).
  void dispose() {
    if (!_active) return;
    _active = false;
    _idle?.cancel();
    unawaited(_closeDownload(delete: true));
    unawaited(_closeUpload());
  }

  void _resetIdle() {
    _idle?.cancel();
    if (!_active || _waitingForUser) return;
    _idle = Timer(limits.idleTimeout, () {
      if (!_active || _waitingForUser) return;
      _finish(error: 'timed out');
    });
  }

  void _notify() {
    if (_active) onChanged();
  }

  void _finish({String? error}) {
    if (!_active) return;
    _active = false;
    _error = error;
    _idle?.cancel();
    _idle = null;
    unawaited(_closeDownload(delete: error != null));
    unawaited(_closeUpload());
    onChanged();
    onDone?.call();
  }

  // ---------------------------------------------------------------------
  // Parsing

  void _drain() {
    if (_draining) return;
    _draining = true;
    try {
      while (_active && !_waitingForUser) {
        final expectation = _expect;
        if (expectation != null) {
          final subpacket = _takeSubpacket();
          if (subpacket == null) break;
          _handleSubpacket(expectation, subpacket);
        } else {
          final header = _takeHeader();
          if (header == null) break;
          _handleHeader(header);
        }
      }
    } on Object catch (error) {
      _finish(error: 'protocol error: $error');
    } finally {
      _draining = false;
    }
  }

  /// The next header, after showing any bytes that are not one.
  _ZHeader? _takeHeader() {
    while (_buffer.isNotEmpty) {
      final at = _findHeader(_buffer);
      if (at == null) {
        // Keep a prefix that may still become a header.
        final keep = _partialHeaderAtEnd(_buffer);
        final garbage = _buffer.sublist(0, _buffer.length - keep);
        _buffer = _buffer.sublist(_buffer.length - keep);
        if (garbage.isNotEmpty) writeOutput(Uint8List.fromList(garbage));
        return null;
      }
      if (at > 0) {
        writeOutput(Uint8List.fromList(_buffer.sublist(0, at)));
        _buffer = _buffer.sublist(at);
      }
      final header = _parseHeaderAtStart();
      if (header != null) return header;
      if (_buffer.isEmpty) return null;
      // Not a header after all: show its first byte and look again.
      writeOutput(Uint8List.fromList([_buffer.first]));
      _buffer = _buffer.sublist(1);
    }
    return null;
  }

  _ZHeader? _parseHeaderAtStart() {
    if (_buffer.length < 4) return null;
    if (_buffer[0] == _zpad &&
        _buffer[1] == _zpad &&
        _buffer[2] == _zdle &&
        _buffer[3] == _zhex) {
      if (_buffer.length < 18) return null;
      final values = <int>[];
      for (var index = 4; index < 18; index += 2) {
        final high = _hexValue(_buffer[index]);
        final low = _hexValue(_buffer[index + 1]);
        if (high == null || low == null) return null;
        values.add((high << 4) | low);
      }
      final type = values[0];
      final data = values.sublist(1, 5);
      final crc = (values[5] << 8) | values[6];
      if (_crc16([type, ...data]) != crc) {
        throw const FormatException('bad hex header CRC');
      }
      // CR LF and XON follow hex headers.
      var end = 18;
      while (end < _buffer.length &&
          (_buffer[end] == 0x0d ||
              _buffer[end] == 0x0a ||
              _buffer[end] == 0x8a ||
              _buffer[end] == 0x11)) {
        end++;
      }
      _buffer = _buffer.sublist(end);
      return _ZHeader(type: type, data: data, crc32: false);
    }
    if (_buffer[0] == _zpad && _buffer[1] == _zdle) {
      final binary = _buffer[2];
      if (binary != _zbin && binary != _zbin32) return null;
      final crcLength = binary == _zbin32 ? 4 : 2;
      final wanted = 1 + 4 + crcLength;
      final values = <int>[];
      var index = 3;
      while (values.length < wanted) {
        if (index >= _buffer.length) return null;
        final byte = _buffer[index++];
        if (byte == _zdle) {
          if (index >= _buffer.length) return null;
          values.add(_buffer[index++] ^ 0x40);
        } else {
          values.add(byte);
        }
      }
      final type = values[0];
      final data = values.sublist(1, 5);
      final crcBytes = values.sublist(5);
      final valid = crcLength == 2
          ? _crc16([type, ...data]) == ((crcBytes[0] << 8) | crcBytes[1])
          : _crc32([type, ...data]) == _u32le(crcBytes);
      if (!valid) throw const FormatException('bad binary header CRC');
      _buffer = _buffer.sublist(index);
      return _ZHeader(type: type, data: data, crc32: crcLength == 4);
    }
    return null;
  }

  /// A data subpacket at the start of the buffer, or null when it is not all
  /// here yet.
  _ZSubpacket? _takeSubpacket() {
    var end = -1;
    var frameEnd = 0;
    for (var index = 0; index + 1 < _buffer.length; index++) {
      if (_buffer[index] == _zdle) {
        final next = _buffer[index + 1];
        if (next >= _zcrce && next <= _zcrcW) {
          end = index;
          frameEnd = next;
          break;
        }
      }
    }
    if (end < 0) {
      if (_buffer.length > limits.maxSubpacket * 2 + 16) {
        throw const FormatException('data subpacket too long');
      }
      return null;
    }
    final crcLength = _dataCrc32 ? 4 : 2;
    final crcBytes = <int>[];
    var index = end + 2;
    while (crcBytes.length < crcLength) {
      if (index >= _buffer.length) return null;
      final byte = _buffer[index++];
      if (byte == _zdle) {
        if (index >= _buffer.length) return null;
        crcBytes.add(_buffer[index++] ^ 0x40);
      } else {
        crcBytes.add(byte);
      }
    }
    final encoded = _buffer.sublist(0, end);
    final payload = _unescape(encoded);
    final covered = [...payload, frameEnd];
    final valid = _dataCrc32
        ? _crc32(covered) == _u32le(crcBytes)
        : _crc16(covered) == ((crcBytes[0] << 8) | crcBytes[1]);
    if (!valid) throw const FormatException('bad data subpacket CRC');
    _buffer = _buffer.sublist(index);
    return _ZSubpacket(payload: payload, frameEnd: frameEnd);
  }

  // ---------------------------------------------------------------------
  // Frames

  void _handleHeader(_ZHeader header) {
    switch (header.type) {
      case _zrqinit:
        _direction ??= ZmodemDirection.download;
        _sendZRinit();
        break;
      case _zrinit:
        _direction ??= ZmodemDirection.upload;
        _escapeCtl = (header.data[3] & 0x40) != 0;
        if (_direction == ZmodemDirection.upload) _receiverReady();
        break;
      case _zsinit:
        _dataCrc32 = header.crc32;
        _expect = _SubpacketExpectation.zsinit;
        break;
      case _zack:
        // An acknowledgement; nothing to do.
        break;
      case _zfile:
        _direction ??= ZmodemDirection.download;
        _dataCrc32 = header.crc32;
        _expect = _SubpacketExpectation.fileInfo;
        break;
      case _zskip:
        if (_direction == ZmodemDirection.upload) _nextUploadFile();
        break;
      case _znak:
        // Whoever asked is retrying; the sender's next header restarts it.
        break;
      case _zabort:
        _finish(error: 'aborted by the other end');
        break;
      case _zfin:
        if (_direction == ZmodemDirection.download) {
          if (!_gotFin) {
            _gotFin = true;
            _sendHeader(_zfin);
          }
          _finish();
        } else if (_sendPhase == _SendPhase.fin) {
          send(Uint8List.fromList(const [0x4f, 0x4f]));
          _finish();
        } else {
          _sendHeader(_zfin);
          _sendPhase = _SendPhase.fin;
        }
        break;
      case _zrpos:
        if (_direction == ZmodemDirection.upload) {
          _requestUploadData(header.offset);
        }
        break;
      case _zdata:
        if (_direction == ZmodemDirection.download) {
          _dataCrc32 = header.crc32;
          final offset = header.offset;
          if (offset != _offset) {
            if (offset < _offset) {
              _truncateDownload(offset);
            } else {
              _discardData = true;
              _sendHeader(_zrpos, data: _le32(_offset));
            }
          } else {
            _discardData = false;
          }
          _expect = _SubpacketExpectation.data;
        }
        break;
      case _zeof:
        if (_direction == ZmodemDirection.download) {
          unawaited(_completeDownload());
        }
        break;
      case _zcrc:
        break;
      default:
        break;
    }
  }

  void _handleSubpacket(_SubpacketExpectation expectation, _ZSubpacket sp) {
    switch (expectation) {
      case _SubpacketExpectation.fileInfo:
        _expect = null;
        _offerFile(sp.payload);
        break;
      case _SubpacketExpectation.zsinit:
        _expect = null;
        _sendHeader(_zack);
        break;
      case _SubpacketExpectation.data:
        if (!_discardData && sp.payload.isNotEmpty) {
          _writeDownload(sp.payload);
        }
        switch (sp.frameEnd) {
          case _zcrce:
            _expect = null;
            break;
          case _zcrcQ || _zcrcW:
            _sendHeader(_zack, data: _le32(_offset));
            break;
          default:
            break;
        }
        break;
    }
  }

  // ---------------------------------------------------------------------
  // Receiving

  void _offerFile(List<int> payload) {
    final nul = payload.indexOf(0);
    final nameBytes = payload.sublist(0, nul < 0 ? payload.length : nul);
    final details = nul < 0
        ? ''
        : utf8.decode(payload.sublist(nul + 1), allowMalformed: true);
    final parts = details.trim().split(RegExp(r'\s+'));
    final size = parts.isNotEmpty ? int.tryParse(parts.first) ?? 0 : 0;
    final name = _localName(utf8.decode(nameBytes, allowMalformed: true));
    _name = name;
    _total = size;
    _transferred = 0;
    _savedPath = null;
    _fileIndex = _finishedFiles + 1;
    _fileCount = math.max(_fileCount, _fileIndex);
    _waitingForUser = true;
    _notify();
    unawaited(_acceptFile(name, size));
  }

  Future<void> _acceptFile(String name, int size) async {
    String? path;
    try {
      path = await pickSaveFile(name);
    } on Object catch (error) {
      _finish(error: 'could not ask where to save: $error');
      return;
    }
    if (!_active) return;
    if (path == null) {
      _waitingForUser = false;
      _sendHeader(_zskip);
      _resetIdle();
      return;
    }
    try {
      final file = File(path);
      await file.parent.create(recursive: true);
      _download = await file.open(mode: FileMode.write);
      _downloadPath = path;
      _savedPath = path;
      _offset = 0;
      _waitingForUser = false;
      _expect = null;
      _notify();
      _sendHeader(_zrpos, data: _le32(0));
      _drain();
      _resetIdle();
    } on Object catch (error) {
      _waitingForUser = false;
      _sendHeader(_zskip);
      _finish(error: 'could not write $path: $error');
    }
  }

  void _writeDownload(List<int> bytes) {
    final file = _download;
    if (file == null) return;
    try {
      file.writeFromSync(bytes);
      _offset += bytes.length;
      _transferred = _offset;
      _notify();
    } on Object catch (error) {
      _finish(error: 'could not save the file: $error');
    }
  }

  // Synchronous on purpose: [_writeDownload] writes synchronously, and an
  // async truncate would overlap with the next subpacket's write on the same
  // handle ("An async operation is currently pending").
  void _truncateDownload(int offset) {
    final file = _download;
    if (file == null) return;
    try {
      file.truncateSync(offset);
      file.setPositionSync(offset);
      _offset = offset;
      _transferred = offset;
      _notify();
    } on Object catch (error) {
      _finish(error: 'could not rewind the file: $error');
    }
  }

  Future<void> _completeDownload() async {
    await _closeDownload();
    if (!_active) return;
    _finishedFiles++;
    _transferred = _total;
    _expect = null;
    _discardData = false;
    _fileIndex = _finishedFiles;
    _notify();
    _sendZRinit();
    _resetIdle();
  }

  Future<void> _closeDownload({bool delete = false}) async {
    final file = _download;
    final path = _downloadPath;
    _download = null;
    _downloadPath = null;
    if (file == null) return;
    try {
      await file.close();
    } on Object {
      // Nothing to do about a file that cannot be closed.
    }
    if (delete && path != null) {
      try {
        await File(path).delete();
      } on Object {
        // The file may never have been created.
      }
    }
  }

  // ---------------------------------------------------------------------
  // Sending

  void _receiverReady() {
    switch (_sendPhase) {
      case _SendPhase.idle:
        _sendPhase = _SendPhase.picking;
        _waitingForUser = true;
        _notify();
        unawaited(_chooseFiles());
      case _SendPhase.waitZrinit:
        _finishedFiles++;
        _nextUploadFile();
      case _SendPhase.fin:
        break;
      default:
        break;
    }
  }

  Future<void> _chooseFiles() async {
    List<String> files;
    try {
      files = await pickFiles();
    } on Object catch (error) {
      _finish(error: 'could not ask for files: $error');
      return;
    }
    if (!_active) return;
    if (files.isEmpty) {
      _waitingForUser = false;
      _sendFin();
      return;
    }
    _files
      ..clear()
      ..addAll(files);
    _fileCount = files.length;
    _fileIndex = 0;
    _direction = ZmodemDirection.upload;
    _waitingForUser = false;
    _sendPhase = _SendPhase.waitZrpos;
    _notify();
    _nextUploadFile();
    _resetIdle();
  }

  void _nextUploadFile() {
    if (!_active) return;
    // Any loop still finishing belongs to the file we are leaving behind.
    _uploadGeneration++;
    _uploadRestart = null;
    unawaited(_startNextUpload());
  }

  Future<void> _startNextUpload() async {
    await _closeUpload();
    if (!_active) return;
    if (_nextFile >= _files.length) {
      _sendFin();
      return;
    }
    final path = _files[_nextFile++];
    _fileIndex = _nextFile;
    _name = p.basename(path);
    _transferred = 0;
    _total = 0;
    _notify();
    await _offerUpload(path);
  }

  Future<void> _offerUpload(String path) async {
    try {
      final file = File(path);
      final size = await file.length();
      final stat = await file.stat();
      final raf = await file.open();
      if (!_active) {
        await raf.close();
        return;
      }
      _upload = raf;
      _uploadSize = size;
      _total = size;
      _sendPhase = _SendPhase.waitZrpos;
      final name = p.basename(path);
      final info = utf8.encode(
        '$name\x00$size ${stat.modified.millisecondsSinceEpoch ~/ 1000} '
        '100644\x00',
      );
      _sendHeader(_zfile, data: const [0, 0, 0, 1], binary: true);
      _sendSubpacket(info, _zcrcW);
      _notify();
      _resetIdle();
      // The receiver may have asked for a position while the file was opening.
      _startUploadLoop();
    } on Object catch (error) {
      if (!_active) return;
      _finish(error: 'could not read $path: $error');
    }
  }

  bool _isSending(int generation) =>
      _active && generation == _uploadGeneration;

  void _startUploadLoop() {
    if (!_active || _upload == null || _uploadLoop != null) return;
    final generation = _uploadGeneration;
    _uploadLoop = _runUpload(generation);
  }

  void _requestUploadData(int offset) {
    _uploadRestart = offset;
    _startUploadLoop();
  }

  Future<void> _runUpload(int generation) async {
    try {
      while (_isSending(generation)) {
        final offset = _uploadRestart;
        if (offset == null) break;
        _uploadRestart = null;
        await _sendUploadData(generation, offset);
      }
    } finally {
      if (generation == _uploadGeneration) _uploadLoop = null;
    }
  }

  Future<void> _sendUploadData(int generation, int start) async {
    final file = _upload;
    if (file == null || !_active) return;
    if (start < 0 || start > _uploadSize) {
      _finish(error: 'the other end asked for a position past the file');
      return;
    }
    _sendPhase = _SendPhase.sending;
    try {
      await file.setPosition(start);
      if (!_isSending(generation)) return;
      var offset = start;
      _transferred = offset;
      _notify();
      var first = true;
      var remaining = _uploadSize - offset;
      if (remaining == 0) {
        _sendHeader(_zdata, data: _le32(offset), binary: true);
        _sendSubpacket(const [], _zcrce);
        first = false;
      }
      while (remaining > 0) {
        if (!_isSending(generation)) return;
        if (_uploadRestart != null) {
          // The receiver moved the position. End the current frame so its
          // parser is looking for headers again, then restart from there.
          if (!first) _sendSubpacket(const [], _zcrce);
          return;
        }
        final chunk = await file.read(math.min(limits.sendChunk, remaining));
        if (!_isSending(generation)) return;
        if (chunk.isEmpty) break;
        if (first) {
          _sendHeader(_zdata, data: _le32(offset), binary: true);
          first = false;
        }
        remaining -= chunk.length;
        offset += chunk.length;
        _sendSubpacket(chunk, remaining == 0 ? _zcrce : _zcrCG);
        _transferred = offset;
        _notify();
        _resetIdle();
        // Let the event loop run (and the screen redraw) on big files.
        if (offset % (limits.sendChunk * 8) == 0) {
          await Future<void>.delayed(const Duration(milliseconds: 1));
        }
      }
      if (!_isSending(generation) || _uploadRestart != null) return;
      // Move to the next phase before writing ZEOF: a receiver that answers
      // immediately must be understood as ready for the next file.
      _sendPhase = _SendPhase.waitZrinit;
      _sendHeader(_zeof, data: _le32(offset));
      _resetIdle();
    } on Object catch (error) {
      if (!_isSending(generation)) return;
      _finish(error: 'could not send the file: $error');
    }
  }

  void _sendFin() {
    _sendHeader(_zfin);
    _sendPhase = _SendPhase.fin;
    _waitingForUser = false;
    _notify();
    _resetIdle();
  }

  Future<void> _closeUpload() async {
    final file = _upload;
    _upload = null;
    _uploadRestart = null;
    final loop = _uploadLoop;
    if (loop != null) {
      try {
        await loop;
      } on Object {
        // The loop reports its own failures.
      }
    }
    if (identical(_uploadLoop, loop)) _uploadLoop = null;
    if (file == null) return;
    try {
      await file.close();
    } on Object {
      // Nothing to do about a file that cannot be closed.
    }
  }

  // ---------------------------------------------------------------------
  // Wire format

  void _sendZRinit() {
    _sendHeader(_zrinit, data: const [0, 0, 0, 0x03]);
  }

  void _sendHeader(
    int type, {
    List<int> data = const [0, 0, 0, 0],
    bool binary = false,
  }) {
    final values = [type, ...data];
    if (binary) {
      final crc = _crc16(values);
      final bytes = _escape([...values, crc >> 8, crc & 0xff], 0);
      send(Uint8List.fromList([_zpad, _zdle, _zbin, ...bytes]));
      return;
    }
    final crc = _crc16(values);
    final body = [...values, crc >> 8, crc & 0xff];
    final hex = StringBuffer();
    for (final byte in body) {
      hex.write(byte.toRadixString(16).padLeft(2, '0'));
    }
    send(
      Uint8List.fromList([
        _zpad,
        _zpad,
        _zdle,
        _zhex,
        ...ascii.encode(hex.toString()),
        0x0d,
        0x0a,
        0x11,
      ]),
    );
  }

  void _sendSubpacket(List<int> payload, int frameEnd) {
    final crc = _crc16([...payload, frameEnd]);
    send(
      Uint8List.fromList([
        ..._escape(payload, 0x00),
        _zdle,
        frameEnd,
        ..._escape([crc >> 8, crc & 0xff], frameEnd),
        if (frameEnd == _zcrcW) 0x11,
      ]),
    );
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
              (previous == 0x40 || previous == 0xc0)) ||
          (_escapeCtl && (byte & 0x60) == 0);
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
}

class ZmodemLimits {
  const ZmodemLimits({
    this.sendChunk = 8192,
    this.maxSubpacket = 1024 * 32,
    this.idleTimeout = const Duration(seconds: 20),
  });

  final int sendChunk;
  final int maxSubpacket;
  final Duration idleTimeout;
}

enum _SubpacketExpectation { fileInfo, zsinit, data }

enum _SendPhase { idle, picking, waitZrpos, sending, waitZrinit, fin }

class _ZHeader {
  const _ZHeader({required this.type, required this.data, required this.crc32});

  final int type;
  final List<int> data;
  final bool crc32;

  int get offset => _u32le(data);
}

class _ZSubpacket {
  const _ZSubpacket({required this.payload, required this.frameEnd});

  final List<int> payload;
  final int frameEnd;
}

const _zpad = 0x2a;
const _zdle = 0x18;
const _zbin = 0x41;
const _zhex = 0x42;
const _zbin32 = 0x43;

const _zrqinit = 0;
const _zrinit = 1;
const _zsinit = 2;
const _zack = 3;
const _zfile = 4;
const _zskip = 5;
const _znak = 6;
const _zabort = 7;
const _zfin = 8;
const _zrpos = 9;
const _zdata = 10;
const _zeof = 11;
const _zcrc = 12;

const _zcrce = 0x68;
const _zcrCG = 0x69;
const _zcrcQ = 0x6a;
const _zcrcW = 0x6b;

int? _hexValue(int byte) {
  if (byte >= 0x30 && byte <= 0x39) return byte - 0x30;
  if (byte >= 0x61 && byte <= 0x66) return byte - 0x61 + 10;
  if (byte >= 0x41 && byte <= 0x46) return byte - 0x41 + 10;
  return null;
}

/// Where a header starts in [bytes], if one is there in full enough form to
/// tell what it is; null when there is none (or only a prefix).
int? _findHeader(Uint8List bytes) {
  for (var index = 0; index + 4 <= bytes.length; index++) {
    if (bytes[index] != _zpad) continue;
    if (bytes[index + 1] == _zpad &&
        bytes[index + 2] == _zdle &&
        bytes[index + 3] == _zhex) {
      if (index + 6 > bytes.length) return null;
      if (_hexValue(bytes[index + 4]) != null &&
          _hexValue(bytes[index + 5]) != null) {
        return index;
      }
      continue;
    }
    if (bytes[index + 1] == _zdle &&
        (bytes[index + 2] == _zbin || bytes[index + 2] == _zbin32)) {
      return index;
    }
  }
  return null;
}

/// Where a hex header that can start a session begins in [bytes]: `**` then
/// ZDLE then ZHEX, with its frame type.
int? findZmodemStart(Uint8List bytes) {
  for (var index = 0; index + 6 <= bytes.length; index++) {
    if (bytes[index] != _zpad ||
        bytes[index + 1] != _zpad ||
        bytes[index + 2] != _zdle ||
        bytes[index + 3] != _zhex) {
      continue;
    }
    if (_hexValue(bytes[index + 4]) != null &&
        _hexValue(bytes[index + 5]) != null) {
      return index;
    }
  }
  return null;
}

/// How many bytes at the end of [bytes] could still become the start of a
/// session's first header.
int zmodemStartPrefixAtEnd(Uint8List bytes) {
  const prefix = [_zpad, _zpad, _zdle, _zhex];
  for (var length = math.min(6, bytes.length); length > 0; length--) {
    final start = bytes.length - length;
    var matches = true;
    for (var index = 0; index < length && index < prefix.length; index++) {
      if (bytes[start + index] != prefix[index]) {
        matches = false;
        break;
      }
    }
    if (matches && length > 4) {
      matches = _hexValue(bytes[start + 4]) != null;
      if (length > 5) {
        matches = matches && _hexValue(bytes[start + 5]) != null;
      }
    }
    if (matches) return length;
  }
  return 0;
}

/// How many bytes at the end of [bytes] could still begin a header.
int _partialHeaderAtEnd(Uint8List bytes) {
  const prefix = [_zpad, _zpad, _zdle, _zhex];
  for (var length = math.min(6, bytes.length); length > 0; length--) {
    final start = bytes.length - length;
    var matches = true;
    for (var index = 0; index < length && index < prefix.length; index++) {
      if (bytes[start + index] != prefix[index]) {
        matches = false;
        break;
      }
    }
    if (matches && length > 4) {
      matches = _hexValue(bytes[start + 4]) != null;
      if (length > 5) {
        matches = matches && _hexValue(bytes[start + 5]) != null;
      }
    }
    if (matches) return length;
  }
  return 0;
}

String _localName(String name) {
  final cleaned = name.replaceAll('\\', '/');
  final base = p.basename(cleaned);
  return base.isEmpty || base == '.' || base == '..' ? 'download' : base;
}

List<int> _le32(int value) => [
  value & 0xff,
  (value >> 8) & 0xff,
  (value >> 16) & 0xff,
  (value >> 24) & 0xff,
];

int _u32le(List<int> bytes) =>
    bytes[0] | (bytes[1] << 8) | (bytes[2] << 16) | (bytes[3] << 24);

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

final Uint32List _crc32Table = () {
  final table = Uint32List(256);
  for (var index = 0; index < 256; index++) {
    var value = index;
    for (var bit = 0; bit < 8; bit++) {
      value = (value & 1) != 0 ? 0xedb88320 ^ (value >> 1) : value >> 1;
    }
    table[index] = value;
  }
  return table;
}();

int _crc32(List<int> bytes) {
  var crc = 0xffffffff;
  for (final byte in bytes) {
    crc = _crc32Table[(crc ^ byte) & 0xff] ^ (crc >> 8);
  }
  return (crc ^ 0xffffffff) & 0xffffffff;
}
