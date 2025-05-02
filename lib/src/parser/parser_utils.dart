/*
 * Copyright © 2020, David PHAM-VAN, <dev.nfet.net@gmail.com>.
 * All rights reserved.
 * Unauthorized copying of this file, via any medium is strictly prohibited
 * Proprietary and confidential
 */

import 'dart:typed_data';

bool compareLists(List<int> A, List<int> B) {
  if (A.length != B.length) {
    return false;
  }

  for (var i = 0; i < A.length; i++) {
    if (A[i] != B[i]) {
      return false;
    }
  }
  return true;
}

class PdfSkippedSpaces {
  const PdfSkippedSpaces(this.data, this.start, this.end, this.found);

  final Uint8List data;
  final int start;
  final int end;
  final bool found;

  @override
  String toString() => String.fromCharCodes(data.sublist(start, end));
}

PdfSkippedSpaces skipSpaces(Uint8List data, int offset) {
  var index = offset;
  var found = false;

  while (index < data.length &&
      (data[index] == 0x00 ||
          data[index] == 0x09 ||
          data[index] == 0x0a ||
          data[index] == 0x0c ||
          data[index] == 0x0d ||
          data[index] == 0x20 ||
          data[index] == 0x25)) {
    if (data[index] == 0x25) {
      // % comments
      index++;
      while (index < data.length && data[index] != 0x0a) {
        index++;
      }
    }
    index++;
    found = true;
  }

  return PdfSkippedSpaces(data, offset, index, found);
}

class PdfParsedLine {
  const PdfParsedLine(this.data, this.start, this.end, this.lineEnd);

  final Uint8List data;
  final int start;
  final int lineEnd;
  final int end;

  bool get isEmpty => start == lineEnd;

  int get length => lineEnd - start;

  @override
  String toString() =>
      String.fromCharCodes(data.sublist(start, lineEnd)).trim();

  int findObject() {
    final s = toString();

    if (s.trimRight().endsWith('obj')) {
      return end;
    }

    final p = s.indexOf(' obj');
    if (p < 0) {
      return p;
    }

    return start + p + 4;
  }
}

PdfParsedLine parseLine(Uint8List data, int offset) {
  // Remove comment and empty lines
  while (data[offset] == 0x25 || data[offset] == 0x0a || data[offset] == 0x0d) {
    while (
        offset < data.length && data[offset] != 0x0a && data[offset] != 0x0d) {
      offset++;
    }
    // Remove empty lines
    while (offset < data.length &&
        (data[offset] == 0x0a || data[offset] == 0x0d)) {
      offset++;
    }
  }

  var index = offset;

  // The actual data
  while (index < data.length &&
      data[index] != 0x0a &&
      data[index] != 0x0d &&
      data[index] != 0x25 /* % */ &&
      data[index] != 0x3c /* < */) {
    index++;
  }

  final lineEnd = index;

  // Remove comments
  if (data[index] == 0x25) {
    while (index < data.length && data[index] != 0x0a && data[index] != 0x0d) {
      index++;
    }
  }

  // Remove empty lines
  while (index < data.length && (data[index] == 0x0a || data[index] == 0x0d)) {
    index++;
  }

  final p = PdfParsedLine(data, offset, index, lineEnd);
  //print('Parsed Line: "$p" ${p.start} ${p.length}');
  return p;
}
