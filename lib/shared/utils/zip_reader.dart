import 'dart:io';
import 'dart:typed_data';

/// The files of a ZIP archive (stored or deflated entries; directories
/// skipped) – for `zip` reports (spec 12.4, Python `file_open`), without
/// an archive package: the central directory is read and deflated data
/// is inflated with `dart:io` (`ZLibDecoder(raw: true)`).
List<({String name, Uint8List bytes})> readZip(Uint8List zip) {
  final data = ByteData.sublistView(zip);
  int u16(int o) => data.getUint16(o, Endian.little);
  int u32(int o) => data.getUint32(o, Endian.little);

  // end of central directory record (at most 64 KiB comment)
  var eocd = -1;
  for (var i = zip.length - 22; i >= 0 && i >= zip.length - 22 - 0xffff; i--) {
    if (u32(i) == 0x06054b50) {
      eocd = i;
      break;
    }
  }
  if (eocd < 0) throw const FormatException('not a zip archive');
  final count = u16(eocd + 10);
  var offset = u32(eocd + 16);
  final files = <({String name, Uint8List bytes})>[];
  for (var n = 0; n < count; n++) {
    if (u32(offset) != 0x02014b50) {
      throw const FormatException('broken central directory');
    }
    final method = u16(offset + 10);
    final compressed = u32(offset + 20);
    final nameLength = u16(offset + 28);
    final extraLength = u16(offset + 30);
    final commentLength = u16(offset + 32);
    final local = u32(offset + 42);
    final name = String.fromCharCodes(
        zip.sublist(offset + 46, offset + 46 + nameLength));
    offset += 46 + nameLength + extraLength + commentLength;
    if (name.endsWith('/')) continue;
    if (u32(local) != 0x04034b50) {
      throw const FormatException('broken local header');
    }
    final start = local + 30 + u16(local + 26) + u16(local + 28);
    final raw = zip.sublist(start, start + compressed);
    final bytes = switch (method) {
      0 => raw,
      8 => Uint8List.fromList(ZLibDecoder(raw: true).convert(raw)),
      _ => throw FormatException('unsupported compression $method'),
    };
    files.add((name: name, bytes: bytes));
  }
  return files;
}
