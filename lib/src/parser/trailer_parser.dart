/*
 * Copyright © 2020, David PHAM-VAN, <dev.nfet.net@gmail.com>.
 * All rights reserved.
 * Unauthorized copying of this file, via any medium is strictly prohibited
 * Proprietary and confidential
 */

import 'dart:typed_data';

import '../pdf.dart';
import 'data_types_parser.dart';
import 'parser_utils.dart';

int trailerParser(Uint8List data, int offset) {
  var index = offset;
  final startxref = 'startxref'.codeUnits;

  while (index > 9) {
    if (compareLists(data.sublist(index - 9, index), startxref)) {
      final n = pdfStreamParser(data, index);
      final nd = n.data;
      if (nd is PdfNum) {
        return nd.value.toInt();
      }
    }
    index--;
  }

  throw Exception('Unable to find the PDF startxref');
}
