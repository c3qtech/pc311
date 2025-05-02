/*
 * Copyright © 2020, David PHAM-VAN, <dev.nfet.net@gmail.com>.
 * All rights reserved.
 * Unauthorized copying of this file, via any medium is strictly prohibited
 * Proprietary and confidential
 */

import '../pdf.dart';
import 'document.dart';
import 'parsed_object.dart';

class ParsedPage {
  const ParsedPage({
    required this.parser,
    required this.ser,
    required this.gen,
    required this.page,
  });

  final PdfDocumentParser parser;
  final int? ser;
  final int gen;
  final PdfDict page;

  PdfIndirect get ref => PdfIndirect(ser!, gen);

  PdfParsedObject get object => parser.xref.getObject(ref);

  Iterable<PdfDictStream> get contents sync* {
    if (!page.containsKey('/Contents')) {
      return;
    }

    if (page['/Contents'] is! PdfArray) {
      yield parser.resolve(page['/Contents']!);
    } else {
      for (final p in (page['/Contents'] as PdfArray).values) {
        yield parser.resolve(p);
      }
    }
  }
}
