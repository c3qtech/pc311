/*
 * Copyright © 2020, David PHAM-VAN, <dev.nfet.net@gmail.com>.
 * All rights reserved.
 * Unauthorized copying of this file, via any medium is strictly prohibited
 * Proprietary and confidential
 */

import 'dart:typed_data';

import 'package:meta/meta.dart';

import '../pdf.dart';
import 'compressed_object_parser.dart';
import 'data_types_parser.dart';
import 'parsed_object.dart';
import 'parsed_object_stream.dart';
import 'parser_utils.dart';

class CrossRefTable {
  factory CrossRefTable(Uint8List data, int offset) {
    PdfParsedDataType? stream;
    final entries = <PdfXref>[];
    final xrefObj = RegExp(r'[\d]*[\s]+[\d]*obj');
    var version = PdfVersion.pdf_1_4;
    final visited = <int>{};

    while (true) {
      if (visited.contains(offset)) {
        break;
      }
      visited.add(offset);
      final xref = parseLine(data, offset);
      final CrossRefTable table;
      if (xrefObj.hasMatch(xref.toString())) {
        table = CrossRefTable.compressed(data, xref.end);
        if (table.version.index > version.index) {
          version = table.version;
        }
      } else {
        if (xref.toString() != 'xref') {
          throw Exception('Unable to find xref ($xref)');
        }
        final offset = xref.end;
        table = CrossRefTable.legacy(data, offset);
      }

      stream ??= table.stream;
      entries.addAll(table.entries);
      final prev = (table.stream.data as PdfDict)['/Prev'];
      if (prev == null) {
        break;
      } else {
        offset = (prev as PdfNum).value.toInt();
        if (offset < 0) {
          break;
        }
      }
    }

    if (stream == null) {
      throw Exception('Malformed PDF file');
    }

    return CrossRefTable._(data, entries, stream, version);
  }

  @visibleForTesting
  factory CrossRefTable.legacy(Uint8List data, int offset) {
    final entries = <PdfXref>[];

    var fl = parseLine(data, offset);
    offset = fl.end;

    while (fl.toString() != 'trailer') {
      final fls = fl.toString().split(' ');
      final first = int.parse(fls[0]);
      final last = first + int.parse(fls[1]);

      for (var n = first; n < last; n++) {
        final xr = parseLine(data, offset);
        final s = xr.toString();

        entries.add(PdfXref(
          n,
          int.parse(s.substring(0, 10)),
          gen: int.parse(s.substring(11, 16)),
          type: s[17] == 'n'
              ? PdfCrossRefEntryType.inUse
              : PdfCrossRefEntryType.free,
        ));

        offset = xr.end;
      }

      fl = parseLine(data, offset);
      offset = fl.end;
    }

    final _stream = pdfStreamParser(data, offset);

    return CrossRefTable._(data, entries, _stream, PdfVersion.pdf_1_4);
  }

  @visibleForTesting
  factory CrossRefTable.compressed(Uint8List data, int offset) {
    final _xref = pdfStreamParser(data, offset);
    if (_xref.data is! PdfDictStream) {
      return CrossRefTable._(data, [], _xref, PdfVersion.pdf_1_4);
    }
    final xref = _xref.data as PdfDictStream;
    if (!xref.values.containsKey('/Size') || !xref.values.containsKey('/W')) {
      return CrossRefTable._(data, [], _xref, PdfVersion.pdf_1_4);
    }
    final size = (xref['/Size']! as PdfNum).value;
    final w = (xref['/W']! as PdfArray)
        .values
        .map<int>((e) => (e as PdfNum).value.toInt())
        .toList();
    final index = ((xref['/Index'] ?? PdfArray.fromNum([0, size])) as PdfArray)
        .values
        .map<int>((e) => (e as PdfNum).value.toInt())
        .toList();

    final table = xref.decode().data;
    final entries = <PdfXref>[];

    var ofs = 0;

    int _readVal(int l) {
      var v = 0;
      for (var n = 0; n < l; n++) {
        v |= table[ofs] << ((l - n - 1) * 8);
        ofs++;
      }
      return v;
    }

    for (var i = 0; i < index.length ~/ 2; i++) {
      final start = index[i * 2];
      final count = index[i * 2 + 1];

      for (var j = 0; j < count; j++) {
        final d = w.map((k) => _readVal(k)).toList();

        switch (d[0]) {
          case 0:
            entries.add(PdfXref(
              start + j,
              d[1],
              gen: d[2],
              type: PdfCrossRefEntryType.free,
            ));
            break;
          case 1:
            entries.add(PdfXref(
              start + j,
              d[1],
              gen: d[2],
              type: PdfCrossRefEntryType.inUse,
            ));
            break;
          case 2:
            entries.add(PdfXref(
              start + j,
              d[2],
              object: d[1],
              type: PdfCrossRefEntryType.compressed,
            ));
            break;
          default:
            throw Exception('Unsupported PDF format');
        }
      }
    }

    return CrossRefTable._(data, entries, _xref, PdfVersion.pdf_1_5);
  }

  CrossRefTable._(this.data, this.entries, this.stream, this.version);

  final List<PdfXref> entries;

  PdfParsedDataType stream;

  PdfDict get params => stream.data as PdfDict;

  final PdfVersion version;

  final Uint8List data;

  PdfXref findObject(PdfIndirect ref) {
    for (final entry in entries) {
      if (ref.ser == entry.ser && ref.gen == entry.gen) {
        return entry;
      }
    }

    throw Exception('Entry not found $ref');
  }

  PdfParsedObject<T> getObject<T extends PdfDataType>(
    PdfIndirect ref, {
    PdfSettings settings = const PdfSettings(verbose: true),
  }) {
    final entry = findObject(ref);

    if (entry.type == PdfCrossRefEntryType.compressed) {
      final container = getObject<PdfDictStream>(entry.container!);
      final co = parseCompressedObjects(container, this);
      return co.getObject<T>(ref.ser, settings: settings);
    }

    var ln = parseLine(data, entry.offset);
    var end = ln.findObject();
    while (end < 0) {
      ln = parseLine(data, ln.end);
      end = ln.findObject();
    }

    final params = pdfStreamParser(data, end, this);

    return PdfParsedObject<T>(
      objser: entry.ser,
      objgen: entry.gen,
      data: params,
      settings: settings,
    );
  }

  T resolve<T extends PdfDataType>(PdfDataType ref) {
    if (ref is PdfIndirect) {
      return getObject<T>(ref).params;
    }

    return ref as T;
  }

  @override
  String toString() {
    final s = StringBuffer();

    s.writeln('CrossRefTable:');
    for (final entry in entries) {
      s.writeln(
          '${entry.ser.toString().padLeft(5, ' ')} ${entry.gen.toString().padLeft(5, ' ')} ${(entry.object?.toString() ?? '').padLeft(5, ' ')} ${entry.offset.toString().padLeft(10, ' ')} ${entry.type}');
    }

    return s.toString();
  }
}
