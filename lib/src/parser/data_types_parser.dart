/*
 * Copyright © 2020, David PHAM-VAN, <dev.nfet.net@gmail.com>.
 * All rights reserved.
 * Unauthorized copying of this file, via any medium is strictly prohibited
 * Proprietary and confidential
 */

import 'dart:math';
import 'dart:typed_data';

import '../pdf.dart';
import 'cross_ref_parser.dart';
import 'parser_utils.dart';

class ParserException implements Exception {
  const ParserException(this.message, this.data, this.offset);

  final String message;

  final Uint8List data;

  final int offset;

  @override
  String toString() {
    final d = data.sublist(max(0, offset - 20), min(data.length, offset + 20));
    return '$message at $offset (${String.fromCharCodes(d)})';
  }
}

class PdfParsedDataType<T extends PdfDataType> {
  const PdfParsedDataType(this.data, this.start, this.end, this.bin);

  final T data;

  final int start;

  final int end;

  final Uint8List bin;

  @override
  String toString() =>
      '[$start:$end] ${data.runtimeType} $data "${String.fromCharCodes(bin.sublist(start, end))}"';
}

PdfParsedDataType pdfStreamParser(Uint8List data, int offset,
    [CrossRefTable? xref]) {
  var index = offset;
  var token = 0;
  while (index < data.length) {
    switch (token) {
      case 0:
        final ss = skipSpaces(data, index);
        if (ss.found) {
          index = ss.end;
        }
        switch (data[index]) {
          case 0x74: // true
            if (data[index + 1] == 0x72 &&
                data[index + 2] == 0x75 &&
                data[index + 3] == 0x65) {
              return PdfParsedDataType(
                  const PdfBool(true), index, index + 4, data);
            }
            throw ParserException('Should be true', data, index);
          case 0x3c: // < hex string or dict
            token = 1;
            break;
          case 0x28: // () literal string
            return _parseStringLiteral(data, index + 1);
          case 0x5b: // [ array
            return _parseArray(data, index + 1, xref);
          case 0x6e: // null
            if (data[index + 1] == 0x75 &&
                data[index + 2] == 0x6c &&
                data[index + 3] == 0x6c) {
              return PdfParsedDataType(const PdfNull(), index, index + 4, data);
            }
            throw ParserException('Should be null', data, index);
          case 0x2f: // /
            return _parseName(data, index + 1);
          case 0x66: // false
            if (data[index + 1] == 0x61 &&
                data[index + 2] == 0x6c &&
                data[index + 3] == 0x73 &&
                data[index + 4] == 0x65) {
              return PdfParsedDataType(
                  const PdfBool(false), index, index + 5, data);
            }
            throw ParserException('Should be false', data, index);
          default:
            if ((data[index] >= 0x30 && data[index] <= 0x39) ||
                data[index] == 0x2e ||
                data[index] == 0x2d ||
                data[index] == 0x2b) {
              return _parseNum(data, index);
            }
            throw ParserException('Invalid state', data, index);
        }
        break;
      case 1: // hex string or dict
        if (data[index] == 0x3c) {
          return _parseDict(data, index + 1, xref);
        }
        return _parseBinaryString(data, index);
      default:
        throw ParserException('Invalid token $token', data, index);
    }
    index++;
  }

  throw ParserException('Invalid stream', data, index);
}

bool _isSpace(int char) => char == 0x20 || char == 0x0a || char == 0x0d;

PdfParsedDataType _parseName(Uint8List data, int offset) {
  var index = offset;
  final name = <int>[];

  while (index < data.length &&
      data[index] >= 0x21 &&
      data[index] <= 0x7e &&
      data[index] != 0x2f &&
      data[index] != 0x5b &&
      data[index] != 0x5d &&
      data[index] != 0x28 &&
      data[index] != 0x3c &&
      data[index] != 0x3e) {
    if (data[index] == 0x23) {
      final s = String.fromCharCodes(data.sublist(index + 1, index + 3));
      name.add(int.parse(s, radix: 16));
      index += 3;
    } else {
      name.add(data[index]);
      index++;
    }
  }

  return PdfParsedDataType(
      PdfName('/${String.fromCharCodes(name)}'), offset - 1, index, data);
}

PdfParsedDataType _parseArray(Uint8List data, int offset, CrossRefTable? xref) {
  var index = offset;
  final array = <PdfDataType>[];

  while (index < data.length && data[index] != 0x5d) {
    final ss = skipSpaces(data, index);
    if (ss.found) {
      index = ss.end;
      continue;
    }

    final item = pdfStreamParser(data, index, xref);
    array.add(item.data);
    index = item.end;
  }

  return PdfParsedDataType(PdfArray(array), offset - 1, index + 1, data);
}

PdfParsedDataType _parseDict(Uint8List data, int offset, CrossRefTable? xref) {
  var index = offset;
  final dict = <String, PdfDataType>{};

  while (index + 1 < data.length) {
    if (data[index] == 0x3e && data[index + 1] == 0x3e) {
      break;
    }
    final ss = skipSpaces(data, index);
    if (ss.found) {
      index = ss.end;
      continue;
    }

    final key = pdfStreamParser(data, index, xref);
    index = key.end;

    final val = pdfStreamParser(data, index, xref);
    index = val.end;

    final name = key.data;
    if (name is PdfName) {
      dict[name.value] = val.data;
    }
  }

  index += 2;

  if (dict.containsKey('/Length')) {
    final int length;
    if (dict['/Length'] is PdfNum) {
      length = (dict['/Length']! as PdfNum).value.toInt();
    } else if (dict['/Length'] is PdfIndirect && xref != null) {
      length = (xref.resolve<PdfNum>(dict['/Length']!)).value.toInt();
    } else {
      throw Exception('Unable to get length');
    }

    var sIndex = index;
    // Might be a PdfDictStream
    final ss = skipSpaces(data, index);
    if (ss.found) {
      sIndex = ss.end;
    }

    // Minimum size
    if (sIndex + length + 15 < data.length) {
      // "stream\n" or "stream\r\n"
      if (data[sIndex] == 0x73 &&
          data[sIndex + 1] == 0x74 &&
          data[sIndex + 2] == 0x72 &&
          data[sIndex + 3] == 0x65 &&
          data[sIndex + 4] == 0x61 &&
          data[sIndex + 5] == 0x6d) {
        sIndex += 6;
        if (data[sIndex] == 0x0d && data[sIndex + 1] == 0x0a) {
          sIndex += 2;
        } else if (data[sIndex] == 0x0a) {
          sIndex++;
        } else {
          throw ParserException('Invalid object stream', data, sIndex);
        }

        final eIndex = sIndex + length;
        index = eIndex;

        while (data[index] == 0x0a || data[index] == 0x0d) {
          index++;
        }

        // "endstream"
        if (index + 8 < data.length &&
            data[index] == 0x65 &&
            data[index + 1] == 0x6e &&
            data[index + 2] == 0x64 &&
            data[index + 3] == 0x73 &&
            data[index + 4] == 0x74 &&
            data[index + 5] == 0x72 &&
            data[index + 6] == 0x65 &&
            data[index + 7] == 0x61 &&
            data[index + 8] == 0x6d) {
          return PdfParsedDataType(
            PdfDictStream(
              values: dict,
              data: data.sublist(sIndex, eIndex),
            ),
            offset - 2,
            index + 9,
            data,
          );
        }

        throw ParserException('Invalid object stream', data, index);
      }
    }
  }

  return PdfParsedDataType(PdfDict(dict), offset - 2, index, data);
}

PdfParsedDataType _parseNum(Uint8List data, int offset) {
  var index = offset;
  final s = <int>[];
  var float = false;

  while (index < data.length &&
      ((data[index] >= 0x30 && data[index] <= 0x39) ||
          data[index] == 0x2e ||
          data[index] == 0x2d ||
          data[index] == 0x2b)) {
    if (data[index] == 0x2e) {
      if (float) {
        break;
      }
      float = true;
    }
    if (s.isNotEmpty && (data[index] == 0x2d || data[index] == 0x2b)) {
      break;
    }
    s.add(data[index]);
    index++;
  }

  if (!float && index < data.length && _isSpace(data[index])) {
    var fwd = index;
    // May be an object reference
    while (fwd < data.length && _isSpace(data[fwd])) {
      fwd++;
    }

    final g = <int>[];

    while (fwd + 1 < data.length && (data[fwd] >= 0x30 && data[fwd] <= 0x39)) {
      g.add(data[fwd]);
      fwd++;
    }

    if (_isSpace(data[fwd])) {
      while (fwd + 1 < data.length && _isSpace(data[fwd])) {
        fwd++;
      }

      if (data[fwd] == 0x52) {
        final obj = String.fromCharCodes(s);
        final gen = String.fromCharCodes(g);
        return PdfParsedDataType(
            PdfIndirect(int.parse(obj), int.parse(gen)), offset, fwd + 1, data);
      }
    }
  }

  final str = String.fromCharCodes(s);
  return PdfParsedDataType(
      PdfNum(float ? double.parse(str) : int.parse(str)), offset, index, data);
}

PdfParsedDataType _parseBinaryString(Uint8List data, int offset) {
  var index = offset;
  final s = <int>[];
  int? p;

  while (index + 1 < data.length &&
      ((data[index] >= 0x30 && data[index] <= 0x39) ||
          (data[index] >= 0x41 && data[index] <= 0x46) ||
          (data[index] >= 0x61 && data[index] <= 0x66))) {
    if (p == null) {
      p = data[index];
    } else {
      final a = String.fromCharCodes([p, data[index]]);
      s.add(int.parse(a, radix: 16));
      p = null;
    }
    index++;
  }

  if (data[index] != 0x3e) {
    throw ParserException('Unable to decode binary string', data, index);
  }

  return PdfParsedDataType(
      PdfString(
        Uint8List.fromList(s),
        format: PdfStringFormat.binary,
        encrypted: false,
      ),
      offset - 1,
      index + 1,
      data);
}

PdfParsedDataType _parseStringLiteral(Uint8List data, int offset) {
  var index = offset;
  final s = <int>[];
  var parenthesis = 0;

  while (index < data.length && (parenthesis != 0 || data[index] != 0x29)) {
    if (data[index] == 0x28) {
      parenthesis++;
    } else if (data[index] == 0x29) {
      parenthesis--;
    } else if (data[index] == 0x5c) {
      index++;
      if (data[index] == 0x6e) {
        // \n => LINE FEED (0Ah)
        s.add(0x0a);
        index++;
        continue;
      } else if (data[index] == 0x72) {
        // \r CARRIAGE RETURN (0Dh)
        s.add(0x0d);
        index++;
        continue;
      } else if (data[index] == 0x74) {
        // \t => HORIZONTAL TAB (09h)
        s.add(0x09);
        index++;
        continue;
      } else if (data[index] == 0x62) {
        // \b => BACKSPACE (08h)
        s.add(0x08);
        index++;
        continue;
      } else if (data[index] == 0x66) {
        // \f => FORM FEED (0Ch)
        s.add(0x0c);
        index++;
        continue;
      } else if (data[index] >= 0x30 && data[index] <= 0x39) {
        // \ddd => Character code ddd (octal)
        final r = String.fromCharCodes(data.sublist(index, index + 3));
        s.add(int.parse(r, radix: 8));
        index += 3;
        continue;
      }
    }
    s.add(data[index]);
    index++;
  }

  return PdfParsedDataType(
      PdfString(
        Uint8List.fromList(s),
        format: PdfStringFormat.literal,
        encrypted: false,
      ),
      offset - 1,
      index + 1,
      data);
}
